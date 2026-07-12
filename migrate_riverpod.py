import os
import re

directories = ['lib/presentation', 'lib/data/services', 'lib/main.dart', 'lib/app.dart']

provider_map = {
    'AuthService.instance': 'ref.read(authServiceProvider)',
    'ApiService.instance': 'ref.read(apiServiceProvider)',
    'AiService.instance': 'ref.read(aiServiceProvider)',
    'LocalDbService.instance': 'ref.read(localDbServiceProvider)',
    'MailService.instance': 'ref.read(mailServiceProvider)',
    'MyprepodService.instance': 'ref.read(myprepodServiceProvider)',
    'ChatStorageService.instance': 'ref.read(chatStorageServiceProvider)',
    'NotificationService.instance': 'ref.read(notificationServiceProvider)',
    'CrossRefService.instance': 'ref.read(crossRefServiceProvider)',
}

def fix_ui_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    original = content

    # 1. Convert StatelessWidget -> ConsumerWidget
    content = re.sub(r'class\s+(\w+)\s+extends\s+StatelessWidget', r'class \1 extends ConsumerWidget', content)
    # 2. Add ref to build method of ConsumerWidget
    content = re.sub(r'Widget\s+build\(\s*BuildContext\s+context\s*\)', r'Widget build(BuildContext context, WidgetRef ref)', content)
    
    # 3. Convert StatefulWidget -> ConsumerStatefulWidget
    content = re.sub(r'class\s+(\w+)\s+extends\s+StatefulWidget', r'class \1 extends ConsumerStatefulWidget', content)
    # 4. Convert State<T> -> ConsumerState<T>
    content = re.sub(r'class\s+(\w+)\s+extends\s+State<(\w+)>', r'class \1 extends ConsumerState<\2>', content)
    
    # 5. Replace instances
    for instance, prov in provider_map.items():
        content = content.replace(instance, prov)
        
    if content != original:
        print(f"Modifying {filepath}")
        
        # Add imports if missing
        if 'flutter_riverpod.dart' not in content:
            content = "import 'package:flutter_riverpod/flutter_riverpod.dart';\n" + content
            
        if 'providers.dart' not in content:
            depth = filepath.replace('\\', '/').count('/') - 1
            if filepath == 'lib/main.dart' or filepath == 'lib/app.dart':
                depth = 0
            if depth < 0: depth = 0
            rel_path = '../' * depth + 'core/providers.dart'
            if depth == 0:
                rel_path = 'core/providers.dart'
            content = f"import '{rel_path}';\n" + content
            
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)

for d in directories:
    if os.path.exists(d):
        if os.path.isfile(d):
            fix_ui_file(d)
        else:
            for root, _, files in os.walk(d):
                for file in files:
                    if file.endswith('.dart'):
                        filepath = os.path.join(root, file)
                        fix_ui_file(filepath)
