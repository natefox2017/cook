import Foundation
import Testing
@testable import RecipeCore

@Test
func sharePosterQRLinksRequireHttpsPublicHostAndOpaqueSlug() throws {
    #expect(RecipePublicShareURL.isValid(
        try #require(URL(string: "https://recipes.example.com/r/aB12cd_99"))))
    for candidate in [
        "http://recipes.example.com/r/aB12cd_99",
        "https://localhost/r/aB12cd_99",
        "https://192.168.1.1/r/aB12cd_99",
        "https://recipes.example.com/r/a",
        "https://name:secret@recipes.example.com/r/aB12cd_99",
        "https://recipes.example.com/r/aB12cd_99#private",
        "https://recipes.example.com/private/aB12cd_99",
        "javascript:alert(1)"
    ] {
        #expect(!RecipePublicShareURL.isValid(try #require(URL(string: candidate))))
    }
}
