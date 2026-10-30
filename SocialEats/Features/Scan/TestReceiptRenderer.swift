import UIKit

enum TestReceiptRenderer {

    static func image(venueName: String, time: Date = Date()) -> UIImage {
        let size = CGSize(width: 800, height: 1100)
        let renderer = UIGraphicsImageRenderer(size: size)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        let lines: [(text: String, big: Bool)] = [
            (venueName.uppercased(), true),
            ("Colombo 07", false),
            ("Date: \(dateFormatter.string(from: time))  Time: \(timeFormatter.string(from: time))", false),
            ("", false),
            ("Chef Special      1,850.00", false),
            ("Side Dish           950.00", false),
            ("Iced Tea            450.00", false),
            ("", false),
            ("Subtotal          3,250.00", false),
            ("Service 10%         325.00", false),
            ("TOTAL LKR 3,575.00", true),
            ("", false),
            ("Thank you!", false)
        ]

        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            var y: CGFloat = 60
            for line in lines {
                let font = UIFont.monospacedSystemFont(ofSize: line.big ? 44 : 30,
                                                       weight: line.big ? .bold : .regular)
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
                (line.text as NSString).draw(at: CGPoint(x: 50, y: y), withAttributes: attributes)
                y += line.big ? 80 : 55
            }
        }
    }
}
