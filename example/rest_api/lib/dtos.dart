import 'package:dartapi_core/dartapi_core.dart';

class BookDTO {
  static final fields = FieldSet({
    'title': Field<String>(
      validators: [NotEmptyValidator(), MaxLengthValidator(200)],
      example: 'Clean Code',
      description: 'Book title',
    ),
    'author': Field<String>(
      validators: [NotEmptyValidator()],
      example: 'Robert C. Martin',
    ),
    'year': Field<int>(
      validators: [RangeValidator(min: 1000, max: 2100)],
      example: 2008,
    ),
  });

  static Map<String, dynamic> get schema => fields.toJsonSchema();

  final String title;
  final String author;
  final int year;

  const BookDTO({
    required this.title,
    required this.author,
    required this.year,
  });

  factory BookDTO.fromJson(Map<String, dynamic> json) {
    fields.validate(json);
    return BookDTO(
      title: json['title'] as String,
      author: json['author'] as String,
      year: json['year'] as int,
    );
  }
}
