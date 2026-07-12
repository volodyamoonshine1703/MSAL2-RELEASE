import 'dart:io';
import 'dart:convert';

void main() async {
  final client = HttpClient();
  
  try {
    final searchUri = Uri.parse('https://myprepod.ru/index.php?page=search&search=' + Uri.encodeComponent('Комаров'));
    final request = await client.getUrl(searchUri);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    
    final results = RegExp(r'<div class="box prep_row".*?>([\s\S]*?)</div>').allMatches(body);
    for (var match in results) {
      print('MATCH: ${match.group(1)}');
    }
    
    if (results.isEmpty) {
        // try another regex if prep_row is not there
        print(body.substring(0, body.length > 2000 ? 2000 : body.length));
    }
  } catch (e) {
    print('Error: $e');
  }
}
