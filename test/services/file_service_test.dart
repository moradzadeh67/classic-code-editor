import 'package:flutter_test/flutter_test.dart';
import 'package:borland_dart/services/file_service.dart';

void main() {
  group('FileService Tests', () {
    late FileService fileService;

    setUp(() {
      fileService = FileService();
    });

    test('initial state has no open tabs', () {
      expect(fileService.openTabs, isEmpty);
      expect(fileService.activeTab, isNull);
      expect(fileService.activeTabIndex, -1);
      expect(fileService.fileName, 'Untitled');
      expect(fileService.fileContent, '');
    });

    test('createNewFile creates an untitled tab', () {
      fileService.createNewFile();

      expect(fileService.openTabs.length, 1);
      expect(fileService.activeTabIndex, 0);
      expect(fileService.fileName, 'Untitled');
      expect(fileService.fileContent, '');
      expect(fileService.isModified, false);
    });

    test('openFilePath opens new file or focuses existing tab', () {
      fileService.openFilePath('/tmp/test.dart', 'void main() {}');

      expect(fileService.openTabs.length, 1);
      expect(fileService.fileName, 'test.dart');
      expect(fileService.fileContent, 'void main() {}');
      expect(fileService.currentFilePath, '/tmp/test.dart');

      // Opening same file again should focus existing tab without duplicating
      fileService.openFilePath('/tmp/other.py', 'print("hello")');
      expect(fileService.openTabs.length, 2);
      expect(fileService.fileName, 'other.py');

      fileService.openFilePath('/tmp/test.dart', 'void main() {} updated');
      expect(fileService.openTabs.length, 2);
      expect(fileService.fileName, 'test.dart');
      expect(fileService.fileContent, 'void main() {}'); // keeps existing or updates? openFilePath doesn't overwrite content if already open
    });

    test('updateContent marks tab as modified', () {
      fileService.createNewFile();
      expect(fileService.isModified, false);

      fileService.updateContent('some new code');
      expect(fileService.fileContent, 'some new code');
      expect(fileService.isModified, true);
    });

    test('switchTab changes active tab correctly', () {
      fileService.openFilePath('/tmp/a.dart', 'a');
      fileService.openFilePath('/tmp/b.dart', 'b');

      expect(fileService.activeTabIndex, 1);
      expect(fileService.fileName, 'b.dart');

      fileService.switchTab(0);
      expect(fileService.activeTabIndex, 0);
      expect(fileService.fileName, 'a.dart');

      // Invalid index bounds check
      fileService.switchTab(5);
      expect(fileService.activeTabIndex, 0);
    });

    test('closeTab removes tab and updates active index', () {
      fileService.openFilePath('/tmp/a.dart', 'a');
      fileService.openFilePath('/tmp/b.dart', 'b');
      fileService.openFilePath('/tmp/c.dart', 'c');

      expect(fileService.openTabs.length, 3);
      expect(fileService.activeTabIndex, 2);

      fileService.closeTab(2);
      expect(fileService.openTabs.length, 2);
      expect(fileService.activeTabIndex, 1);
      expect(fileService.fileName, 'b.dart');

      fileService.closeTab(0);
      expect(fileService.openTabs.length, 1);
      expect(fileService.activeTabIndex, 0);
      expect(fileService.fileName, 'b.dart');

      fileService.closeTab(0);
      expect(fileService.openTabs, isEmpty);
      expect(fileService.activeTabIndex, -1);
      expect(fileService.fileName, 'Untitled');
    });
  });
}
