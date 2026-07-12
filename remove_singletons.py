import os
import re
directory = 'lib/data/services'
for f in os.listdir(directory):
    if f.endswith('.dart'):
        filepath = os.path.join(directory, f)
        with open(filepath, 'r', encoding='utf-8') as file:
            c = file.read()
            
        original = c
        
        if 'myprepod' in f: classname = 'MyprepodService'
        elif 'api' in f: classname = 'ApiService'
        elif 'auth' in f: classname = 'AuthService'
        elif 'ai' in f: classname = 'AiService'
        elif 'local_db' in f: classname = 'LocalDbService'
        elif 'mail' in f: classname = 'MailService'
        elif 'chat_storage' in f: classname = 'ChatStorageService'
        elif 'notification' in f: classname = 'NotificationService'
        elif 'cross_ref' in f: classname = 'CrossRefService'
        else: continue
        
        # Remove singleton
        c = re.sub(rf'{classname}\._\(\);\s*static final {classname} instance = {classname}\._\(\);', rf'{classname}();', c)
        
        if c != original:
            print(f"Removed singleton from {f}")
            with open(filepath, 'w', encoding='utf-8') as file:
                file.write(c)
