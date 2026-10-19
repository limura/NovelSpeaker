import XCTest
import UIKit
@testable import NovelSpeaker

final class UIImageResizeTest: XCTestCase {
    private func makeImage(size: CGSize = CGSize(width: 80, height: 40), scale: CGFloat = 1) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testInvalidAndSubpixelRequestsReturnOriginalImage() {
        let image = makeImage()
        let invalid: [CGFloat] = [0, -1, .nan, .infinity, -.infinity, .leastNonzeroMagnitude, 0.5]
        for value in invalid {
            XCTAssertTrue(image.resize(newSize: CGSize(width: value, height: 40)) === image)
            XCTAssertTrue(image.resize(newSize: CGSize(width: 80, height: value)) === image)
        }
    }

    func testEmptySourceReturnsOriginalImage() {
        let image = UIImage()
        XCTAssertTrue(image.resize(newSize: CGSize(width: 100, height: 100)) === image)
    }

    func testResizeFitsRequestedBoundsAndPreservesAspectRatio() {
        let resized = makeImage().resize(newSize: CGSize(width: 30, height: 30))
        XCTAssertEqual(resized.size, CGSize(width: 30, height: 15))
        XCTAssertEqual(resized.scale, 1)
        XCTAssertEqual(resized.cgImage?.width, 30)
        XCTAssertEqual(resized.cgImage?.height, 15)
    }

    func testHugeRequestDoesNotUpscaleOrAllocateAnotherImage() {
        let image = makeImage()
        let resized = image.resize(newSize: CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                   height: CGFloat.greatestFiniteMagnitude))
        XCTAssertTrue(resized === image)
    }

    func testPixelDimensionsAreCappedForLargeAndScaledSources() {
        let image = makeImage(size: CGSize(width: 1200, height: 600), scale: 2)
        let resized = image.resize(newSize: CGSize(width: 10000, height: 10000))
        XCTAssertEqual(resized.cgImage?.width, 1024)
        XCTAssertEqual(resized.cgImage?.height, 512)
        XCTAssertEqual(resized.scale, 1)
    }

    func testArtworkCanBeRequestedOnBackgroundQueue() {
        let image = makeImage()
        let finished = expectation(description: "background artwork resize")
        DispatchQueue.global().async {
            let resized = image.resize(newSize: CGSize(width: 20, height: 20))
            XCTAssertEqual(resized.size, CGSize(width: 20, height: 10))
            XCTAssertNotNil(resized.cgImage)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5)
    }
}
