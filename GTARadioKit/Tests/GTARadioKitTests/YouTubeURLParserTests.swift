import XCTest
@testable import GTARadioKit

final class YouTubeURLParserTests: XCTestCase {

    // MARK: Video URLs

    func testWatchURL() {
        XCTAssertEqual(YouTubeURLParser.parse("https://www.youtube.com/watch?v=jfKfPfyJRdk"),
                       .video(id: "jfKfPfyJRdk"))
    }

    func testShortURL() {
        XCTAssertEqual(YouTubeURLParser.parse("https://youtu.be/jfKfPfyJRdk"),
                       .video(id: "jfKfPfyJRdk"))
    }

    func testShortURLWithTimestamp() {
        XCTAssertEqual(YouTubeURLParser.parse("https://youtu.be/jfKfPfyJRdk?t=42"),
                       .video(id: "jfKfPfyJRdk"))
    }

    func testShortsURL() {
        XCTAssertEqual(YouTubeURLParser.parse("https://www.youtube.com/shorts/abcDEF12345"),
                       .video(id: "abcDEF12345"))
    }

    func testLiveURL() {
        XCTAssertEqual(YouTubeURLParser.parse("https://www.youtube.com/live/abcDEF12345"),
                       .video(id: "abcDEF12345"))
    }

    func testEmbedURL() {
        XCTAssertEqual(YouTubeURLParser.parse("https://www.youtube.com/embed/abcDEF12345"),
                       .video(id: "abcDEF12345"))
    }

    func testWatchURLWithExtraParams() {
        XCTAssertEqual(YouTubeURLParser.parse("https://www.youtube.com/watch?app=desktop&v=jfKfPfyJRdk&feature=share"),
                       .video(id: "jfKfPfyJRdk"))
    }

    func testWatchWithPlaylistContextIsVideo() {
        // A watch URL is a video URL even when a list param tags along.
        XCTAssertEqual(YouTubeURLParser.parse("https://www.youtube.com/watch?v=jfKfPfyJRdk&list=PLabc123"),
                       .video(id: "jfKfPfyJRdk"))
    }

    func testMobileHost() {
        XCTAssertEqual(YouTubeURLParser.parse("https://m.youtube.com/watch?v=jfKfPfyJRdk"),
                       .video(id: "jfKfPfyJRdk"))
    }

    func testMusicHost() {
        XCTAssertEqual(YouTubeURLParser.parse("https://music.youtube.com/watch?v=jfKfPfyJRdk"),
                       .video(id: "jfKfPfyJRdk"))
    }

    func testSchemelessURL() {
        XCTAssertEqual(YouTubeURLParser.parse("youtube.com/watch?v=jfKfPfyJRdk"),
                       .video(id: "jfKfPfyJRdk"))
    }

    func testHTTPUpgraded() {
        XCTAssertEqual(YouTubeURLParser.parse("http://www.youtube.com/watch?v=jfKfPfyJRdk"),
                       .video(id: "jfKfPfyJRdk"))
    }

    // MARK: Playlist URLs

    func testPlaylistURL() {
        XCTAssertEqual(YouTubeURLParser.parse("https://www.youtube.com/playlist?list=PLHFlHpPjgk706qEJf9fkclIhdhTkH49Tf"),
                       .playlist(id: "PLHFlHpPjgk706qEJf9fkclIhdhTkH49Tf"))
    }

    func testEmbedVideoseriesPlaylist() {
        XCTAssertEqual(YouTubeURLParser.parse("https://www.youtube.com/embed/videoseries?list=PLabc123"),
                       .playlist(id: "PLabc123"))
    }

    // MARK: Channel URLs

    func testChannelIDURL() {
        XCTAssertEqual(YouTubeURLParser.parse("https://www.youtube.com/channel/UCSJ4gkVC6NrvII8umztf0Ow"),
                       .channelID("UCSJ4gkVC6NrvII8umztf0Ow"))
    }

    func testHandleURL() {
        XCTAssertEqual(YouTubeURLParser.parse("https://www.youtube.com/@LofiGirl"),
                       .handle("LofiGirl"))
    }

    func testHandleURLWithSubpath() {
        XCTAssertEqual(YouTubeURLParser.parse("https://www.youtube.com/@LofiGirl/videos"),
                       .handle("LofiGirl"))
    }

    func testCustomNameURL() {
        XCTAssertEqual(YouTubeURLParser.parse("https://www.youtube.com/c/LofiGirl"),
                       .customName("LofiGirl"))
    }

    func testLegacyUserURL() {
        XCTAssertEqual(YouTubeURLParser.parse("https://www.youtube.com/user/marquesbrownlee"),
                       .legacyUser("marquesbrownlee"))
    }

    // MARK: Rejects

    func testNonYouTubeHostRejected() {
        XCTAssertNil(YouTubeURLParser.parse("https://vimeo.com/watch?v=jfKfPfyJRdk"))
    }

    func testGarbageRejected() {
        XCTAssertNil(YouTubeURLParser.parse("not a url at all"))
    }

    func testEmptyStringRejected() {
        XCTAssertNil(YouTubeURLParser.parse("   "))
    }

    func testBadVideoIDLengthRejected() {
        XCTAssertNil(YouTubeURLParser.parse("https://www.youtube.com/watch?v=short"))
    }

    func testWhitespacePaddedURLAccepted() {
        XCTAssertEqual(YouTubeURLParser.parse("  https://youtu.be/jfKfPfyJRdk\n"),
                       .video(id: "jfKfPfyJRdk"))
    }
}
