import re
from pathlib import Path
p=Path('lib/main.dart');s=p.read_text()
s=s.replace('const Row(\n        children: [\n          for (final d', 'Row(\n        children: [\n          for (final d')
s=re.sub(r'const Row\((\s*children:\s*\[\s*for \(final d)',r'Row(\1',s)
if 'void refreshState' not in s:
    s,n=re.subn(r'(class _LifeKeeperState extends State<LifeKeeper>\s+with WidgetsBindingObserver\s*\{)',r'\1\n  void refreshState(VoidCallback change) { if (mounted) setState(change); }',s)
    if n!=1:raise ValueError('State class not found')
p.write_text(s)
p=Path('lib/ui/settings.dart');s=p.read_text();s=s.replace('setState(', 'refreshState(');p.write_text(s)
