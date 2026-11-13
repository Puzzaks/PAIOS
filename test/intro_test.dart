import 'package:flutter_test/flutter_test.dart';
import 'package:geminilocal/storage/intro_slide_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IntroSlideRepository Tests', () {
    test('getIcon maps common icon names to Material IconData', () {
      expect(IntroSlideRepository.getIcon('forum_rounded'), isNotNull);
      expect(IntroSlideRepository.getIcon('volunteer_activism_rounded'), isNotNull);
      expect(IntroSlideRepository.getIcon('hub_rounded'), isNotNull);
      expect(IntroSlideRepository.getIcon('unknown_icon'), isNotNull);
    });

    test('getSlidesForBranch filters correctly by active branch', () {
      final repo = IntroSlideRepository(notifyEngine: () {});
      repo.slides = [
        {"id": "slide_all", "branch": "all"},
        {"id": "slide_supp", "branch": "supported"},
        {"id": "slide_unsupp", "branch": "unsupported"},
      ];

      final supportedSlides = repo.getSlidesForBranch(true);
      expect(supportedSlides.map((s) => s["id"]), containsAll(["slide_all", "slide_supp"]));
      expect(supportedSlides.map((s) => s["id"]), isNot(contains("slide_unsupp")));

      final unsupportedSlides = repo.getSlidesForBranch(false);
      expect(unsupportedSlides.map((s) => s["id"]), containsAll(["slide_all", "slide_unsupp"]));
      expect(unsupportedSlides.map((s) => s["id"]), isNot(contains("slide_supp")));
    });
  });
}
