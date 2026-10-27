void main() {
  final numbers = [12, 7, 3, 19, 24, 8, 15, 6, 11, 30];
  final evens = numbers.where((n) => n % 2 == 0).toList();
  final odds = numbers.where((n) => n % 2 != 0).toList();
  print('اعداد: $numbers');
  print('زوج‌ها: $evens');
  print('فردها: $odds');
  print('مجموع زوج‌ها: ${evens.reduce((a, b) => a + b)}');
  print('مجموع فردها: ${odds.reduce((a, b) => a + b)}');
  print('میانگین: ${numbers.reduce((a, b) => a + b) / numbers.length}');
  print('بیشینه: ${numbers.reduce((a, b) => a > b ? a : b)}');
  print('کمینه: ${numbers.reduce((a, b) => a < b ? a : b)}');
  final sorted = List<int>.from(numbers)..sort();
  print('مرتب‌شده: $sorted');
  print('مربع‌ها: ${numbers.map((n) => n * n).toList()}');
  print('بزرگ‌تر از ۱۰: ${numbers.where((n) => n > 10).length} عدد');
}