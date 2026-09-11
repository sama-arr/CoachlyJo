#!/usr/bin/env python3
"""
Coachly — static checks for the Flutter frontend.

Runs without the Dart toolchain. It catches the classes of error that have
actually bitten this project, so a build can be sanity-checked anywhere:

  1. unbalanced braces/parens/brackets (tokenizer-based: handles comments,
     strings, triple-quoted strings and ${...} interpolation)
  2. relative imports that do not resolve
  3. references to classes that are never defined
  4. package: imports missing from pubspec.yaml
  5. StatefulWidget without a matching State<...>
  6. deprecated / stale API usage (withOpacity, retired endpoints)
  7. const contexts containing runtime i18n calls -- these do NOT compile
  8. private methods declared but never used (analyzer warnings)
  9. frontend API paths that do not exist in the backend routes

Usage:  python3 tools/static_checks.py          (from the repo root)
        python3 tools/static_checks.py frontend

`flutter analyze` remains the authoritative check; this is the pre-flight.
"""
import os
import re
import sys

root = sys.argv[1] if len(sys.argv) > 1 else 'frontend'
lib = os.path.join(root, 'lib')
backend_src = os.path.join(os.path.dirname(root) or '.', 'backend', 'src')
if not os.path.isdir(lib):
    lib = 'lib'
    backend_src = os.path.join('..', 'backend', 'src')

errors = []
files = []
for dirpath, _, names in os.walk(lib):
    for n in names:
        if n.endswith('.dart'):
            files.append(os.path.join(dirpath, n))

if not files:
    print(f'No Dart files found under {lib}')
    sys.exit(1)


def strip_code(src):
    """Remove comments and string contents, keeping ${...} interpolation code."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '/' and i + 1 < n and src[i + 1] == '/':
            while i < n and src[i] != '\n':
                i += 1
            continue
        if c == '/' and i + 1 < n and src[i + 1] == '*':
            i += 2
            while i + 1 < n and not (src[i] == '*' and src[i + 1] == '/'):
                i += 1
            i += 2
            continue
        if c in ('"', "'"):
            q = c
            triple = src[i:i + 3] == q * 3
            i += 3 if triple else 1
            while i < n:
                if src[i] == '\\':
                    i += 2
                    continue
                if src[i] == '$' and i + 1 < n and src[i + 1] == '{':
                    depth = 1
                    out.append('{')
                    i += 2
                    while i < n and depth > 0:
                        if src[i] == '{':
                            depth += 1
                        elif src[i] == '}':
                            depth -= 1
                        if depth > 0:
                            out.append(src[i])
                        i += 1
                    out.append('}')
                    continue
                if triple and src[i:i + 3] == q * 3:
                    i += 3
                    break
                if not triple and src[i] == q:
                    i += 1
                    break
                i += 1
            continue
        out.append(c)
        i += 1
    return ''.join(out)


# 1. balance
for path in files:
    code = strip_code(open(path).read())
    for op, cl, name in [('{', '}', 'braces'), ('(', ')', 'parens'), ('[', ']', 'brackets')]:
        if code.count(op) != code.count(cl):
            errors.append(f'{path}: unbalanced {name} ({code.count(op)} vs {code.count(cl)})')

# 2. relative imports resolve
for path in files:
    for m in re.finditer(r"import\s+'([^']+)'", open(path).read()):
        imp = m.group(1)
        if imp.startswith(('package:', 'dart:')):
            continue
        target = os.path.normpath(os.path.join(os.path.dirname(path), imp))
        if not os.path.exists(target):
            errors.append(f'{path}: missing import {imp}')

# 3. referenced classes exist
defined = set()
for path in files:
    defined.update(re.findall(r'\bclass\s+([A-Za-z_]\w*)', open(path).read()))
WATCHED = [
    'LinkText', 'StatCard', 'StatGrid', 'SimpleBarChart', 'RangePicker', 'ErrorRetry',
    'SettingsScreen', 'ApiClient', 'AuthState', 'ApiException', 'AppConfig', 'MemberHome',
    'CoachHome', 'AdminHome', 'LoginScreen', 'RegisterScreen', 'ForgotPasswordScreen',
    'CoachlyWordmark', 'GradientButton', 'GradientRule', 'Brand', 'GlowBackground',
    'BrandHeader', 'StatusEdgeCard', 'HeroPanel', 'HeroStat', 'BrandCard', 'GradientAvatar',
    'StatusPill', 'EmptyState', 'GradientIconBadge', 'CoachMemberDetail', 'AdminPackagesScreen',
    'HomeScreen', 'AppLang', 'FadeInUp', 'ProgressRing', 'SkeletonBox', 'AnimatedCounter',
    'PressableCard',
]
for path in files:
    src = open(path).read()
    for cls in WATCHED:
        if re.search(r'\b' + cls + r'\b', src) and cls not in defined:
            errors.append(f'{path}: references undefined class {cls}')

# 4. package imports declared
pubspec_path = os.path.join(root, 'pubspec.yaml')
pubspec = open(pubspec_path).read() if os.path.exists(pubspec_path) else ''
for path in files:
    for m in re.finditer(r"import\s+'package:([a-z_0-9]+)/", open(path).read()):
        pkg = m.group(1)
        if pkg in ('flutter', 'flutter_localizations'):
            continue
        if pkg not in pubspec:
            errors.append(f'{path}: package {pkg} not declared in pubspec.yaml')

# 5. StatefulWidget has State
for path in files:
    src = open(path).read()
    for m in re.finditer(r'class\s+(\w+)\s+extends\s+StatefulWidget', src):
        w = m.group(1)
        if f'State<{w}>' not in src:
            errors.append(f'{path}: {w} has no matching State<{w}>')

# 6. stale / deprecated usage
STALE = ['_addTemplate', 'slot-templates', 'slot_templates', 'withOpacity(']
for path in files:
    src = open(path).read()
    for pat in STALE:
        if pat in src:
            errors.append(f'{path}: stale or deprecated usage: {pat}')

# 7. const contexts containing runtime i18n calls (will not compile)
I18N = r'\b(tr|fmtDate|pkgName|noteBody|trStatus)\('
for path in files:
    src = open(path).read()
    for m in re.finditer(r'const\s*[\[\(]', src):
        start = m.end() - 1
        depth, i = 0, start
        while i < len(src):
            if src[i] in '([':
                depth += 1
            elif src[i] in ')]':
                depth -= 1
                if depth == 0:
                    break
            i += 1
        if re.search(I18N, src[start:i + 1]):
            line = src[:m.start()].count('\n') + 1
            errors.append(f'{path}:{line}: const context contains a runtime i18n call (will not compile)')

# 8. unused private methods
for path in files:
    src = open(path).read()
    for m in re.finditer(r'\n\s*(?:Future<[^>]*>|void|Widget|String|int|bool|double)\s+(_[A-Za-z]\w*)\s*\(', src):
        name = m.group(1)
        if len(re.findall(r'\b' + re.escape(name) + r'\b', src)) < 2:
            line = src[:m.start()].count('\n') + 1
            errors.append(f'{path}:{line}: private method {name} is never used')

# 9. frontend API paths exist in the backend
backend = ''
if os.path.isdir(backend_src):
    for dirpath, _, names in os.walk(backend_src):
        for n in names:
            if n.endswith('.js'):
                backend += open(os.path.join(dirpath, n)).read()
api_paths = set()
for path in files:
    src = open(path).read()
    for m in re.finditer(r"'(/api/[a-z\-/]+?)[?']", src):
        api_paths.add(m.group(1))
    for m in re.finditer(r"'(/api/[a-z\-/]*?)\$\{?", src):
        api_paths.add(m.group(1).rstrip('/'))
if backend:
    for p in sorted(api_paths):
        parts = p.split('/api/', 1)[1].split('/')
        needle = '/' + '/'.join(parts[1:]) if len(parts) >= 2 else '/'
        if needle not in backend and parts[0] not in backend:
            errors.append(f'API path not found in backend: {p}')

print(f'Checked {len(files)} Dart files · {len(api_paths)} API paths')
if errors:
    print('\n'.join(errors))
    print(f'\n{len(errors)} problem(s) found.')
    sys.exit(1)
print('STATIC CHECKS PASS')
