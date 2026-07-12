import os

directories = ['lib/data/services', 'lib/data/models']

import_statement = "import '../../core/utils/log.dart' as logger;\n"
import_statement_models = "import '../../core/utils/log.dart' as logger;\n"

for d in directories:
    for root, _, files in os.walk(d):
        for file in files:
            if file.endswith('.dart'):
                filepath = os.path.join(root, file)
                with open(filepath, 'r', encoding='utf-8') as f:
                    content = f.read()
                
                if 'print(' in content:
                    print(f"Fixing {filepath}")
                    
                    # check if already imported
                    if 'core/utils/log.dart' not in content:
                        # find where to insert: after last import or at top
                        lines = content.split('\n')
                        last_import = -1
                        for i, line in enumerate(lines):
                            if line.startswith('import '):
                                last_import = i
                        
                        if last_import != -1:
                            lines.insert(last_import + 1, import_statement.strip())
                        else:
                            lines.insert(0, import_statement.strip())
                        
                        content = '\n'.join(lines)
                    
                    # replace print( with logger.log(
                    # But we only want to replace actual print calls.
                    # regex \bprint(
                    import re
                    content = re.sub(r'\bprint\(', 'logger.log(', content)
                    
                    with open(filepath, 'w', encoding='utf-8') as f:
                        f.write(content)
