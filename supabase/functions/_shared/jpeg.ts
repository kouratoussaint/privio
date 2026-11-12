// Vérification et nettoyage d'une photo JPEG, sans la décoder.
//
// Le fichier est relu segment par segment et RÉÉCRIT en ne gardant que ce qui sert à
// l'afficher : tables de quantification et de Huffman, en-têtes d'image et de balayage,
// données compressées, JFIF (APP0) et Adobe (APP14, couleurs). Tout le reste est retiré :
// EXIF (position GPS, appareil, date, miniature), XMP, ICC, commentaires, et toute donnée
// ajoutée après la fin de l'image (vidéo des « photos animées », par exemple).
// Formats acceptés : JPEG de base, étendu et progressif (SOF0, SOF1, SOF2), 1 ou 3 composantes.

import { MediaError } from "./mp4.ts";

const invalid = () => new MediaError("MEDIA_INVALID");

const KEEP = new Set([
  0xc0, 0xc1, 0xc2, // SOF de base / étendu / progressif
  0xc4, // DHT
  0xdb, // DQT
  0xdd, // DRI
  0xe0, // APP0 (JFIF)
  0xee, // APP14 (Adobe)
]);
const UNSUPPORTED_SOF = new Set([0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcc, 0xcd, 0xce, 0xcf]);

export interface CleanJpeg {
  bytes: Uint8Array;
  width: number;
  height: number;
}

export function cleanJpeg(input: Uint8Array): CleanJpeg {
  const b = input;
  const n = b.length;
  if (n < 4 || b[0] !== 0xff || b[1] !== 0xd8) throw invalid();
  const parts: Uint8Array[] = [b.subarray(0, 2)];
  let p = 2;
  let width = 0;
  let height = 0;
  let sawSos = false;
  let ended = false;
  const u16 = (at: number) => {
    if (at + 1 >= n) throw invalid();
    return (b[at] << 8) | b[at + 1];
  };

  while (p < n) {
    if (b[p] !== 0xff) throw invalid();
    while (p < n && b[p] === 0xff) p++; // octets de remplissage
    if (p >= n) throw invalid();
    const marker = b[p];
    const start = p - 1;
    p++;
    if (marker === 0xd9) {
      parts.push(new Uint8Array([0xff, 0xd9]));
      ended = true;
      break; // tout ce qui suit la fin de l'image est ignoré
    }
    if (marker === 0x00 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7) || marker === 0xd8) {
      throw invalid();
    }
    const length = u16(p);
    if (length < 2 || p + length > n) throw invalid();
    const end = p + length;
    if (UNSUPPORTED_SOF.has(marker)) throw invalid();
    if (marker === 0xc0 || marker === 0xc1 || marker === 0xc2) {
      if (width) throw invalid(); // une seule image
      if (length < 8) throw invalid();
      height = u16(p + 3);
      width = u16(p + 5);
      const components = b[p + 7];
      if (!width || !height || (components !== 1 && components !== 3)) throw invalid();
    }

    if (marker === 0xda) {
      if (!width) throw invalid();
      // En-tête de balayage, puis données compressées jusqu'au prochain vrai marqueur
      // (0xFF00 = octet de donnée, 0xFFD0-D7 = repère de redémarrage).
      let q = end;
      while (q < n) {
        if (b[q] === 0xff && q + 1 < n) {
          const next = b[q + 1];
          if (next === 0x00 || (next >= 0xd0 && next <= 0xd7) || next === 0xff) {
            q += next === 0xff ? 1 : 2;
            continue;
          }
          break;
        }
        q++;
      }
      if (q >= n) throw invalid(); // pas de fin d'image
      parts.push(b.subarray(start, q));
      sawSos = true;
      p = q;
      continue;
    }
    if (KEEP.has(marker)) parts.push(b.subarray(start, end));
    // sinon (APP1-13, APP15, COM, segments inconnus) : retiré
    p = end;
  }
  if (!ended || !sawSos) throw invalid();

  const total = parts.reduce((s, x) => s + x.length, 0);
  const out = new Uint8Array(total);
  let at = 0;
  for (const part of parts) {
    out.set(part, at);
    at += part.length;
  }
  return { bytes: out, width, height };
}
