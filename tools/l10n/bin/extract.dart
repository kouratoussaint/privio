// Lot 8.2a : liste tous les littéraux de chaîne de lib/ (hors chaînes imbriquées), avec
// leur contexte, au format JSON. Le tri « texte affiché ou non » se fait ensuite.
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

void main(List<String> args) {
  final root = Directory(args[0]);
  final out = <Map<String, Object?>>[];
  for (final f in root.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart') || f.path.contains('/l10n/gen/')) continue;
    final src = f.readAsStringSync();
    final unit = parseString(content: src, path: f.path, throwIfDiagnostics: false).unit;
    unit.accept(_Visitor(f.path, src, out));
  }
  stdout.write(jsonEncode(out));
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.path, this.src, this.out);
  final String path;
  final String src;
  final List<Map<String, Object?>> out;

  @override
  void visitAdjacentStrings(AdjacentStrings node) => _emit(node);

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) => _emit(node);

  @override
  void visitStringInterpolation(StringInterpolation node) => _emit(node);

  void _emit(StringLiteral node) {
    final parts = <Object>[]; // String ou Expression
    void collect(StringLiteral s) {
      if (s is SimpleStringLiteral) {
        parts.add(s.value);
      } else if (s is AdjacentStrings) {
        for (final x in s.strings) {
          collect(x);
        }
      } else if (s is StringInterpolation) {
        for (final e in s.elements) {
          if (e is InterpolationString) {
            parts.add(e.value);
          } else if (e is InterpolationExpression) {
            parts.add(e.expression);
          }
        }
      }
    }

    collect(node);
    final holders = <Map<String, Object?>>[];
    final buf = StringBuffer();
    var nested = false;
    for (final p in parts) {
      if (p is String) {
        buf.write(p);
      } else {
        final e = p as Expression;
        var hasString = false;
        e.accept(_FindString(() => hasString = true));
        nested = nested || hasString;
        holders.add({'expr': e.toSource(), 'start': e.offset, 'end': e.end});
        buf.write('\u0000${holders.length - 1}\u0000');
      }
    }
    // Contexte.
    AstNode? n = node.parent;
    String? call;
    String? named;
    var inConst = false;
    var inKey = false;
    var compared = false;
    String? decl;
    var isCase = false;
    var isDefault = false;
    var isIndex = false;
    var isMapKey = false;
    var isAnnotation = false;
    var isDirective = false;
    String? enclosing;
    final p0 = node.parent;
    if (p0 is NamedExpression) named = p0.name.label.name;
    if (p0 is IndexExpression && p0.index == node) isIndex = true;
    if (p0 is MapLiteralEntry && p0.key == node) isMapKey = true;
    if (p0 is BinaryExpression) compared = true;
    if (p0 is DefaultFormalParameter) isDefault = true;
    var depth = 0;
    while (n != null) {
      depth++;
      if (n is InstanceCreationExpression) {
        final t = n.constructorName.type.name.lexeme;
        if (depth <= 3 && (t == 'Key' || t == 'ValueKey' || t == 'ObjectKey')) inKey = true;
        if (n.keyword?.lexeme == 'const') inConst = true;
        call ??= t;
      } else if (n is MethodInvocation) {
        if (depth <= 3 && (n.methodName.name == 'Key' || n.methodName.name == 'ValueKey')) {
          inKey = true;
        }
        call ??= n.methodName.name;
      } else if (n is TypedLiteral && n.constKeyword != null) {
        inConst = true;
      } else if (n is VariableDeclarationList) {
        if (n.isConst) inConst = true;
        final pp = n.parent;
        if (pp is TopLevelVariableDeclaration) decl ??= 'top';
        if (pp is FieldDeclaration) decl ??= pp.isStatic ? 'static' : 'field';
      } else if ((n is ConstantPattern && depth == 1) ||
          (n is SwitchCase && n.expression == node)) {
        isCase = true;
      } else if (n is Annotation) {
        isAnnotation = true;
      } else if (n is Directive) {
        isDirective = true;
      } else if (n is FormalParameterList) {
        // valeur par défaut d'un paramètre
        if (node.thisOrAncestorOfType<DefaultFormalParameter>() != null) isDefault = true;
      } else if (n is ConstructorDeclaration && n.constKeyword != null) {
        // initialiseurs const
      }
      if (enclosing == null) {
        if (n is MethodDeclaration) enclosing = n.name.lexeme;
        if (n is FunctionDeclaration) enclosing = n.name.lexeme;
      }
      if (n is ClassDeclaration) {
        enclosing = '${n.name.lexeme}.${enclosing ?? ''}';
        break;
      }
      n = n.parent;
    }
    final line = src.substring(0, node.offset).split('\n').length;
    out.add({
      'file': path,
      'line': line,
      'start': node.offset,
      'end': node.end,
      'source': node.toSource(),
      'text': buf.toString(),
      'holders': holders,
      'nested': nested,
      'call': call,
      'named': named,
      'const': inConst,
      'key': inKey,
      'compared': compared,
      'decl': decl,
      'case': isCase,
      'default': isDefault,
      'index': isIndex,
      'mapKey': isMapKey,
      'annotation': isAnnotation,
      'directive': isDirective,
      'enclosing': enclosing,
    });
  }

  // Ne pas descendre dans les chaînes : seules les chaînes de premier niveau comptent.
  @override
  void visitInterpolationExpression(InterpolationExpression node) {}
}

class _FindString extends RecursiveAstVisitor<void> {
  _FindString(this.found);
  final void Function() found;
  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) => found();
  @override
  void visitStringInterpolation(StringInterpolation node) => found();
}
