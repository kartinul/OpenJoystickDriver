import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct NameRulesTests {
  @Test
  func trimsOuterWhitespaceBeforeCreating() {
    #expect(ProfileNameValidation.trimmedName("  Arcade  ") == "Arcade")
  }

  @Test
  func rejectsWhitespaceOnlyNamesEvenWhenADeviceIsSelected() {
    #expect(ProfileNameValidation.trimmedName(" \n\t ").isEmpty)
  }
}
