//
//  Confetti.swift
//  Confetti
//
//  Created by Umar Haroon on 8/15/21.
//
import SwiftUI
//import Foundation
struct Confetti: UIViewRepresentable {
    typealias UIViewType = ConfettiView
    func makeUIView(context: Context) -> ConfettiView {
        return ConfettiView()
    }
    
    func updateUIView(_ uiView: ConfettiView, context: Context) {
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.5) {
            uiView.emit(with: [
                ConfettiView.ConfettiContent.shape(.square, .systemPurple),
                ConfettiView.ConfettiContent.shape(.circle, .systemPurple),
                ConfettiView.ConfettiContent.shape(.square, .systemPink),
                ConfettiView.ConfettiContent.shape(.circle, .systemPink),
                ConfettiView.ConfettiContent.shape(.square, .systemBlue),
                ConfettiView.ConfettiContent.shape(.circle, .systemBlue),
                ConfettiView.ConfettiContent.shape(.square, .systemTeal),
                ConfettiView.ConfettiContent.shape(.circle, .systemTeal),
                ConfettiView.ConfettiContent.shape(.circle, .magenta),
                ConfettiView.ConfettiContent.shape(.square, .magenta),
                ConfettiView.ConfettiContent.shape(.square, .systemOrange),
                ConfettiView.ConfettiContent.shape(.circle, .systemOrange),
                ConfettiView.ConfettiContent.shape(.square, .systemYellow),
                ConfettiView.ConfettiContent.shape(.circle, .systemYellow),
            ])
        }
        return
    }
    
    
    
}
final class ConfettiView: UIView {
    public enum ConfettiContent {
        /// Confetti shapes
        public enum Shape: Equatable {
            /// A circle.
            case circle
            
            /// A triangle.
            case triangle
            
            /// A square.
            case square
            
            // A custom shape.
            case custom(CGPath)
        }
        
        /// A shape with a particular color.
        case shape(Shape, UIColor)
        
        /// An image with an optional tint color.
        case image(UIImage, UIColor?)
        
        /// A string of characters.
        case text(String)
    }
    
    private final class ConfettiLayer: CAEmitterLayer {
        func configure(with contents: [ConfettiContent]) {
            emitterCells = contents.map({ content in
                let cell = CAEmitterCell()
                cell.birthRate = 50
                cell.lifetime = 10
                cell.velocity = CGFloat(cell.birthRate * cell.lifetime)
                cell.velocityRange = cell.velocity / 2
                cell.emissionLongitude = .pi
                cell.emissionRange = .pi / 4
                cell.spinRange = .pi * 8
                cell.scaleRange = 0.35
                cell.scale = 1.0 - cell.scaleRange
                cell.contents = content.image.cgImage
                
                if let color = content.color {
                    cell.color = color.cgColor
                }
                
                return cell
            })
        }
        override func layoutSublayers() {
            super.layoutSublayers()
            emitterShape = .line
            emitterSize = CGSize(width: frame.size.width, height: 1.0)
            emitterPosition = CGPoint(x: frame.size.width / 2, y: 0)
        }
    }
    private let kAnimationLayerKey = "com.komodo.animationLayer"
    func emit(with contents: [ConfettiContent], for duration: TimeInterval = 3.0) {
        let layer = ConfettiLayer()
        layer.configure(with: contents)
        layer.frame = self.bounds
        layer.needsDisplayOnBoundsChange = true
        self.layer.addSublayer(layer)
        
        guard duration.isFinite else { return }
        
        let animation = CAKeyframeAnimation(keyPath: #keyPath(CAEmitterLayer.birthRate))
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        animation.values = [1, 0, 0]
        animation.keyTimes = [0, 0.5, 1]
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        
        layer.beginTime = CACurrentMediaTime()
        layer.birthRate = 1
        
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            let transition = CATransition()
            transition.delegate = self
            transition.type = .fade
            transition.duration = 1
            transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
            transition.setValue(layer, forKey: self.kAnimationLayerKey)
            transition.isRemovedOnCompletion = false
            
            layer.add(transition, forKey: nil)
            
            layer.opacity = 0
        }
        layer.add(animation, forKey: nil)
        CATransaction.commit()
    }
    override func willMove(toSuperview newSuperview: UIView?) {
        guard let superView = newSuperview else { return }
        frame = superView.bounds
    }
}
extension ConfettiView: CAAnimationDelegate {
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        if let layer = anim.value(forKey: kAnimationLayerKey) as? CALayer {
            layer.removeAllAnimations()
            layer.removeFromSuperlayer()
        }
    }
}
fileprivate extension ConfettiView.ConfettiContent.Shape {
    func path(in rect: CGRect) -> CGPath {
        switch self {
        case .circle:
            return CGPath(ellipseIn: rect, transform: nil)
        case .triangle:
            let path = CGMutablePath()
            path.addLines(between: [
                CGPoint(x: rect.midX, y: 0),
                CGPoint(x: rect.maxX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.maxY),
                CGPoint(x: rect.midX, y: 0)
            ])
            
            return path
        case .square:
            let rect2 = CGRect(origin: .zero, size: CGSize(width: 12.0, height: 18.0))
            return CGPath(rect: rect2, transform: nil)
        case .custom(let path):
            return path
        }
    }
    
    func image(with color: UIColor, type: ConfettiView.ConfettiContent.Shape) -> UIImage {
        var rect = CGRect(origin: .zero, size: CGSize(width: 10, height: 10.0))
        if type == .square {
            rect = CGRect(origin: .zero, size: CGSize(width: 12.0, height: 18.0))
        }
        return UIGraphicsImageRenderer(size: rect.size).image { context in
            context.cgContext.setFillColor(color.cgColor)
            context.cgContext.addPath(path(in: rect))
            context.cgContext.fillPath()
        }
    }
}

fileprivate extension ConfettiView.ConfettiContent {
    var color: UIColor? {
        switch self {
        case let .image(_, color?),
             let .shape(_, color):
            return color.withAlphaComponent(0.7)
        default:
            return nil
        }
    }
    
    var image: UIImage {
        switch self {
        case let .shape(shape, _):
            return shape.image(with: .white, type: shape)
        case let .image(image, _):
            return image
        case let .text(string):
            let defaultAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16.0)
            ]
            
            return NSAttributedString(string: "\(string)", attributes: defaultAttributes).image()
        }
    }
}

fileprivate extension NSAttributedString {
    func image() -> UIImage {
        return UIGraphicsImageRenderer(size: size()).image { _ in
            self.draw(at: .zero)
        }
    }
}
