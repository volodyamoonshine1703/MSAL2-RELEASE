import re

filepath = 'lib/data/services/auth_service.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

# Remove _buildDio(); calls
content = re.sub(r'\s*_buildDio\(\);', '', content)

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(content)

filepath = 'lib/data/services/mail_service.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace class MailService { \n MailService(); 
# with class MailService { \n final Ref ref; \n MailService(this.ref);
content = re.sub(r'class MailService \{\s*MailService\(\);', 'class MailService {\n  final Ref ref;\n  MailService(this.ref);', content)

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(content)

print("Fixed both services!")
