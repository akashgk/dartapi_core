import 'package:dartapi_core/dartapi_core.dart';

class Book implements Serializable {
  final int id;
  final String title;
  final String author;
  final int year;

  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.year,
  });

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'year': year,
      };
}
