import os
import re

directory = 'lib/presentation'

for root, _, files in os.walk(directory):
    for file in files:
        if file.endswith('.dart'):
            filepath = os.path.join(root, file)
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()
            original = content
            
            # Fix createState return type:
            # State<MyWidget> createState() => _MyWidgetState();
            content = re.sub(r'State<([^>]+)>\s+createState\(\)', r'ConsumerState<\1> createState()', content)
            
            # Fix build method inside ConsumerState
            # We need to only change build(BuildContext context, WidgetRef ref) back to build(BuildContext context)
            # if the class extends ConsumerState. But wait, in dart you can just do a regex replace if you are sure.
            # Only ConsumerWidget needs the ref. ConsumerState doesn't.
            # But wait, my previous script blindly replaced ALL `Widget build(BuildContext context)`.
            # We can distinguish by looking at the class definition.
            # Let's split by "class ".
            classes = content.split('class ')
            for i in range(1, len(classes)):
                if 'extends ConsumerState<' in classes[i]:
                    classes[i] = classes[i].replace('Widget build(BuildContext context, WidgetRef ref)', 'Widget build(BuildContext context)')
            content = 'class '.join(classes)
            
            if content != original:
                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(content)
                print(f"Fixed {file}")
