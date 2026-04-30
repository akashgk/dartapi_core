import 'models.dart';
import 'dtos.dart';

class BookRepository {
  final List<Book> _books = [
    const Book(id: 1, title: 'Clean Code', author: 'Robert C. Martin', year: 2008),
    const Book(id: 2, title: 'The Pragmatic Programmer', author: 'David Thomas', year: 1999),
    const Book(id: 3, title: 'Designing Data-Intensive Applications', author: 'Martin Kleppmann', year: 2017),
  ];
  int _nextId = 4;

  List<Book> getAll({int page = 1, int limit = 20}) {
    final offset = (page - 1) * limit;
    return _books.skip(offset).take(limit).toList();
  }

  int get total => _books.length;

  Book? getById(int id) => _books.where((b) => b.id == id).firstOrNull;

  Book create(BookDTO dto) {
    final book = Book(id: _nextId++, title: dto.title, author: dto.author, year: dto.year);
    _books.add(book);
    return book;
  }

  Book? update(int id, BookDTO dto) {
    final idx = _books.indexWhere((b) => b.id == id);
    if (idx == -1) return null;
    final updated = Book(id: id, title: dto.title, author: dto.author, year: dto.year);
    _books[idx] = updated;
    return updated;
  }

  bool delete(int id) {
    final idx = _books.indexWhere((b) => b.id == id);
    if (idx == -1) return false;
    _books.removeAt(idx);
    return true;
  }
}
