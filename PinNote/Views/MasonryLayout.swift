import UIKit

protocol MasonryLayoutDelegate: AnyObject {
    /// Height of the item when laid out at `itemWidth`.
    func masonryLayout(_ layout: MasonryLayout, heightForItemAt indexPath: IndexPath, itemWidth: CGFloat) -> CGFloat
}

/// Equal-width columns where every item goes into the currently shortest column,
/// so tiles of different heights pack tightly. Items keep their order: the first
/// ones fill the top row from left to right.
final class MasonryLayout: UICollectionViewLayout {

    weak var delegate: MasonryLayoutDelegate?
    var numberOfColumns = 2
    var spacing: CGFloat = 12
    var horizontalInset: CGFloat = 16

    private var itemAttributes: [UICollectionViewLayoutAttributes] = []
    private var contentHeight: CGFloat = 0
    private var deletingIndexPaths = Set<IndexPath>()
    private var insertingIndexPaths = Set<IndexPath>()

    override func prepare() {
        super.prepare()
        itemAttributes = []
        contentHeight = 0
        guard let collectionView, collectionView.numberOfSections > 0 else { return }

        let columns = max(1, numberOfColumns)
        let available = collectionView.bounds.width - horizontalInset * 2 - spacing * CGFloat(columns - 1)
        let itemWidth = floor(available / CGFloat(columns))
        guard itemWidth > 0 else { return }

        var columnHeights = Array(repeating: CGFloat(0), count: columns)
        for item in 0..<collectionView.numberOfItems(inSection: 0) {
            let indexPath = IndexPath(item: item, section: 0)
            // Ties go to the leftmost column.
            let shortest = columnHeights.min() ?? 0
            let column = columnHeights.firstIndex(of: shortest) ?? 0
            let height = ceil(delegate?.masonryLayout(self, heightForItemAt: indexPath, itemWidth: itemWidth) ?? itemWidth)

            let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
            attributes.frame = CGRect(
                x: horizontalInset + CGFloat(column) * (itemWidth + spacing),
                y: columnHeights[column],
                width: itemWidth,
                height: height
            )
            itemAttributes.append(attributes)
            columnHeights[column] += height + spacing
        }
        contentHeight = max(0, (columnHeights.max() ?? 0) - spacing)
    }

    override var collectionViewContentSize: CGSize {
        CGSize(width: collectionView?.bounds.width ?? 0, height: contentHeight)
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        itemAttributes.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.section == 0, itemAttributes.indices.contains(indexPath.item) else { return nil }
        return itemAttributes[indexPath.item]
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.width != collectionView?.bounds.width
    }

    // MARK: - Insert / delete animations

    override func prepare(forCollectionViewUpdates updateItems: [UICollectionViewUpdateItem]) {
        super.prepare(forCollectionViewUpdates: updateItems)
        deletingIndexPaths = Set(updateItems.compactMap { $0.updateAction == .delete ? $0.indexPathBeforeUpdate : nil })
        insertingIndexPaths = Set(updateItems.compactMap { $0.updateAction == .insert ? $0.indexPathAfterUpdate : nil })
    }

    override func finalizeCollectionViewUpdates() {
        super.finalizeCollectionViewUpdates()
        deletingIndexPaths.removeAll()
        insertingIndexPaths.removeAll()
    }

    override func finalLayoutAttributesForDisappearingItem(at itemIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        let attributes = super.finalLayoutAttributesForDisappearingItem(at: itemIndexPath)?.copy() as? UICollectionViewLayoutAttributes
        if deletingIndexPaths.contains(itemIndexPath) {
            attributes?.alpha = 0
            attributes?.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }
        return attributes
    }

    override func initialLayoutAttributesForAppearingItem(at itemIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        let attributes = super.initialLayoutAttributesForAppearingItem(at: itemIndexPath)?.copy() as? UICollectionViewLayoutAttributes
        if insertingIndexPaths.contains(itemIndexPath) {
            attributes?.alpha = 0
            attributes?.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }
        return attributes
    }
}
