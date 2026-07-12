import re

filepath = 'lib/data/services/mail_service.dart'

with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

# Fix authenticate
content = content.replace('await _smtp!.authenticate(_email!, _password!, mech);', 'await _smtp!.authenticate(_email!, password, mech);')

# Fix reconnects: if (_email != null && _password != null) -> if (_email != null)
content = content.replace('if (_email != null && _password != null) {', 'if (_email != null) {')

# Fix connect(_email!, _password!) -> connect(_email!)
content = content.replace('await connect(_email!, _password!);', 'await connect(_email!);')

# Fix OwaContactSearch in lines 417-419
#         final owaSearch = OwaContactSearch(username: _email!, password: _password!);
content = content.replace('password: _password!', "password: (await _secureStorage.read(key: 'saved_password'))!")

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(content)

print("Fixed mail_service.dart")
