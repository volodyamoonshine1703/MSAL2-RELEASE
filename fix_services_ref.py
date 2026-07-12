import os
import re

directory = 'lib/data/services'

for root, _, files in os.walk(directory):
    for file in files:
        if file.endswith('.dart'):
            filepath = os.path.join(root, file)
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()
            original = content
            
            classname = file.replace('_service.dart', 'Service').replace('owa_contact_search.dart', 'OwaContactSearch').title().replace('_', '')
            if 'myprepod' in file: classname = 'MyprepodService'
            elif 'api' in file: classname = 'ApiService'
            elif 'auth' in file: classname = 'AuthService'
            elif 'ai' in file: classname = 'AiService'
            elif 'local_db' in file: classname = 'LocalDbService'
            elif 'mail' in file: classname = 'MailService'
            elif 'chat_storage' in file: classname = 'ChatStorageService'
            elif 'notification' in file: classname = 'NotificationService'
            elif 'cross_ref' in file: classname = 'CrossRefService'
            else: continue
            
            # Need to add Riverpod import if missing
            if 'package:flutter_riverpod/flutter_riverpod.dart' not in content:
                content = "import 'package:flutter_riverpod/flutter_riverpod.dart';\n" + content
                
            if classname == 'AuthService':
                # AuthService has:
                # class AuthService {
                #   final Dio dio;
                #
                #   AuthService(this.dio);
                content = re.sub(r'class AuthService \{\s*final Dio dio;\s*AuthService\(this\.dio\);', 
                                 'class AuthService {\n  final Dio _dio;\n  final Ref ref;\n\n  AuthService(this._dio, this.ref);', content)
                # also fix remaining _dio errors by doing nothing since they are already _dio
                # Wait, I renamed _dio to dio, so the errors say `_dio isn't defined`. If I change it back to _dio, those errors disappear!
                
            else:
                # All other services:
                # class ClassName {
                #   ClassName();
                content = re.sub(rf'class {classname} {{\s*{classname}\(\);', 
                                 f'class {classname} {{\n  final Ref ref;\n  {classname}(this.ref);', content)
                                 
            if content != original:
                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(content)
                print(f"Fixed {file}")
