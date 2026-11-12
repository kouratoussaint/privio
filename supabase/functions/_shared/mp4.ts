// Mesure d'un fichier audio MP4/M4A (AAC) sans le décoder ni en lire le contenu sonore.
//
// La durée retenue est la PLUS LONGUE de trois sources :
//   * l'en-tête du film (mvhd) ;
//   * l'en-tête de chaque piste (mdhd) ;
//   * la table des échantillons (stts) : Σ nombre × durée des échantillons. C'est elle qui
//     fixe le minutage réel de la lecture : un fichier dont les en-têtes « mentent »
//     (durée courte annoncée, son long en réalité) est donc refusé quand même.
// Exigences : boîte ftyp en tête, un seul moov, au moins une piste, TOUTES les pistes sont
// du son (hdlr = « soun ») encodé en AAC (stsd = « mp4a »), pas de fragments (moof).

export class MediaError extends Error {
  constructor(readonly code: string) {
    super(code);
  }
}

interface Box {
  type: string;
  start: number;
  end: number;
  body: number;
}

const invalid = () => new MediaError("MEDIA_INVALID");

function readBoxes(v: DataView, from: number, to: number): Box[] {
  const out: Box[] = [];
  let p = from;
  while (p < to) {
    if (p + 8 > to) throw invalid();
    let size = v.getUint32(p);
    const type = String.fromCharCode(
      v.getUint8(p + 4),
      v.getUint8(p + 5),
      v.getUint8(p + 6),
      v.getUint8(p + 7),
    );
    let header = 8;
    if (size === 1) {
      if (p + 16 > to || v.getUint32(p + 8) !== 0) throw invalid();
      size = v.getUint32(p + 12);
      header = 16;
    } else if (size === 0) {
      size = to - p;
    }
    if (size < header || p + size > to) throw invalid();
    out.push({ type, start: p, end: p + size, body: p + header });
    p += size;
    if (out.length > 10000) throw invalid();
  }
  return out;
}

const children = (v: DataView, b: Box) => readBoxes(v, b.body, b.end);

function only(list: Box[], type: string): Box {
  const found = list.filter((b) => b.type === type);
  if (found.length !== 1) throw invalid();
  return found[0];
}

function need(v: DataView, b: Box, bytes: number) {
  if (b.body + bytes > b.end) throw invalid();
}

/** Échelle de temps et durée d'un en-tête mvhd ou mdhd (versions 0 et 1). */
function timeHeader(v: DataView, b: Box): { timescale: number; duration: number } {
  need(v, b, 4);
  const version = v.getUint8(b.body);
  if (version === 1) {
    need(v, b, 32);
    const timescale = v.getUint32(b.body + 20);
    const duration = Number(v.getBigUint64(b.body + 24));
    return { timescale, duration };
  }
  if (version !== 0) throw invalid();
  need(v, b, 20);
  return { timescale: v.getUint32(b.body + 12), duration: v.getUint32(b.body + 16) };
}

const toMs = (units: number, timescale: number) => {
  if (!Number.isFinite(units) || units < 0 || timescale <= 0) throw invalid();
  return (units * 1000) / timescale;
};

export interface AudioInfo {
  durationMs: number;
}

export function measureAudio(bytes: Uint8Array): AudioInfo {
  const v = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const top = readBoxes(v, 0, bytes.byteLength);
  if (top.length === 0 || top[0].type !== "ftyp") throw invalid();
  if (top.some((b) => b.type === "moof" || b.type === "mfra")) throw invalid();
  if (!top.some((b) => b.type === "mdat")) throw invalid();
  const moov = only(top, "moov");
  const moovKids = children(v, moov);

  const mvhd = timeHeader(v, only(moovKids, "mvhd"));
  let longest = toMs(mvhd.duration, mvhd.timescale);

  const traks = moovKids.filter((b) => b.type === "trak");
  if (traks.length === 0) throw invalid();
  for (const trak of traks) {
    const mdia = only(children(v, trak), "mdia");
    const mdiaKids = children(v, mdia);

    const hdlr = only(mdiaKids, "hdlr");
    need(v, hdlr, 12);
    const handler = String.fromCharCode(
      v.getUint8(hdlr.body + 8),
      v.getUint8(hdlr.body + 9),
      v.getUint8(hdlr.body + 10),
      v.getUint8(hdlr.body + 11),
    );
    if (handler !== "soun") throw invalid();

    const mdhd = timeHeader(v, only(mdiaKids, "mdhd"));
    longest = Math.max(longest, toMs(mdhd.duration, mdhd.timescale));

    const stbl = only(children(v, only(mdiaKids, "minf")), "stbl");
    const stblKids = children(v, stbl);

    const stsd = only(stblKids, "stsd");
    need(v, stsd, 16);
    if (v.getUint32(stsd.body + 4) < 1) throw invalid();
    const codec = String.fromCharCode(
      v.getUint8(stsd.body + 12),
      v.getUint8(stsd.body + 13),
      v.getUint8(stsd.body + 14),
      v.getUint8(stsd.body + 15),
    );
    if (codec !== "mp4a") throw invalid();

    const stts = only(stblKids, "stts");
    need(v, stts, 8);
    const entries = v.getUint32(stts.body + 4);
    need(v, stts, 8 + entries * 8);
    let units = 0;
    for (let i = 0; i < entries; i++) {
      const at = stts.body + 8 + i * 8;
      units += v.getUint32(at) * v.getUint32(at + 4);
    }
    if (units <= 0) throw invalid();
    longest = Math.max(longest, toMs(units, mdhd.timescale));
  }
  return { durationMs: Math.ceil(longest) };
}
