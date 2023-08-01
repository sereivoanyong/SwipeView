//
//  SwipeView.swift
//
//  Created by Yong Sereivoan on 31/7/23.
//

import UIKit

@objc public enum SwipeViewAlignment: Int {

  case edge
  case center
}

@objc public enum SwipeViewScrollDirection: Int {

  case horizontal
  case vertical
}

@objc public protocol SwipeViewDataSource: NSObjectProtocol {

  func numberOfItems(in swipeView: SwipeView) -> Int
  func swipeView(_ swipeView: SwipeView, viewForItemAt index: Int, reusing view: UIView?) -> UIView
}

@objc public protocol SwipeViewDelegate: NSObjectProtocol {

  @objc optional func swipeViewItemSize(_ swipeView: SwipeView) -> CGSize
  @objc optional func swipeViewDidScroll(_ swipeView: SwipeView)
  @objc optional func swipeViewCurrentItemIndexDidChange(_ swipeView: SwipeView)
  @objc optional func swipeViewWillBeginDragging(_ swipeView: SwipeView)
  @objc optional func swipeViewDidEndDragging(_ swipeView: SwipeView, willDecelerate decelerate: Bool)
  @objc optional func swipeViewWillBeginDecelerating(_ swipeView: SwipeView)
  @objc optional func swipeViewDidEndDecelerating(_ swipeView: SwipeView)
  @objc optional func swipeViewDidEndScrollingAnimation(_ swipeView: SwipeView)
  @objc optional func swipeView(_ swipeView: SwipeView, shouldSelectItemAt index: Int) -> Bool
  @objc optional func swipeView(_ swipeView: SwipeView, didSelectItemAt index: Int)
}

open class SwipeView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {

  private var _scrollView: UIScrollView!
  private var _itemViews: [Int: UIView] = [:]
  private var _itemViewPool: Set<UIView> = []
  private var _previousItemIndex: Int = 0
  private var _previousContentOffset: CGPoint!
  private var _suppressScrollEvent: Bool = false
  private var _scrollDuration: TimeInterval = 0
  private var _startTime: TimeInterval = 0
  private var _lastTime: TimeInterval = 0
  private var _startOffset: CGFloat = 0
  private var _endOffset: CGFloat = 0
  private var _lastUpdateOffset: CGFloat = 0
  private var _timer: Timer!

  private var _dataSource: SwipeViewDataSource?
  @IBOutlet open weak var dataSource: SwipeViewDataSource? {
    get { return _dataSource }
    set(dataSource) {
      guard _dataSource !== dataSource else { return }
      _dataSource = dataSource
      if _dataSource != nil {
        reloadData()
      }
    }
  }

  private var _delegate: SwipeViewDelegate?
  @IBOutlet open weak var delegate: SwipeViewDelegate? {
    get { return _delegate }
    set(delegate) {
      guard _delegate !== delegate else { return }
      _delegate = delegate
      setNeedsLayout()
    }
  }

  private var _numberOfItems: Int = 0
  open var numberOfItems: Int {
    return _numberOfItems
  }

  private var _numberOfPages: Int = 0
  open var numberOfPages: Int {
    return Int(ceil(CGFloat(self.numberOfItems) / CGFloat(_itemsPerPage)))
  }

  private var _itemSize: CGSize = .zero
  open var itemSize: CGSize {
    return _itemSize
  }

  private var _itemsPerPage: Int = 1
  open var itemsPerPage: Int {
    get { return _itemsPerPage }
    set(itemsPerPage) {
      guard _itemsPerPage != itemsPerPage else { return }
      _itemsPerPage = itemsPerPage
      setNeedsLayout()
    }
  }

  private var _truncateFinalPage: Bool = false
  open var truncateFinalPage: Bool {
    get { return _truncateFinalPage }
    set(truncateFinalPage) {
      guard _truncateFinalPage != truncateFinalPage else { return }
      _truncateFinalPage = truncateFinalPage
      setNeedsLayout()
    }
  }

  // MARK: View management

  open var indexesForVisibleItems: [Int] {
    return _itemViews.keys.sorted(by: <)
  }

  open var visibleItemViews: [UIView] {
    let indexes = indexesForVisibleItems
    return indexes.compactMap { _itemViews[$0] }
  }

  open func itemView(at index: Int) -> UIView? {
    return _itemViews[index]
  }

  open var currentItemView: UIView? {
    return itemView(at: _currentItemIndex)
  }

  open func indexOfItemView(_ view: UIView?) -> Int? {
    for (index, itemView) in _itemViews {
      if itemView == view {
        return index
      }
    }
    return nil
  }

  open func indexOfItemViewOrSubview(_ view: UIView?) -> Int? {
    let index = indexOfItemView(view)
    if index == nil && view != nil && view != _scrollView {
      return indexOfItemViewOrSubview(view?.superview)
    }
    return index
  }

  private var _currentItemIndex: Int = 0
  open var currentItemIndex: Int {
    get { return _currentItemIndex }
    set(currentItemIndex) {
      _currentItemIndex = currentItemIndex
      self.scrollOffset = CGFloat(_currentItemIndex)
    }
  }

  open var currentPage: Int {
    get {
      if _itemsPerPage > 1 && _truncateFinalPage && !_wrapEnabled && _currentItemIndex > (_numberOfItems / _itemsPerPage - 1) * _itemsPerPage {
        return self.numberOfPages - 1
      }
      return Int(round(CGFloat(_currentItemIndex) / CGFloat(_itemsPerPage)))
    }
    set(currentPage) {
      if currentPage * _itemsPerPage != _currentItemIndex {
        scrollToPage(currentPage, duration: 0)
      }
    }
  }

  private var _alignment: SwipeViewAlignment = .center
  open var alignment: SwipeViewAlignment {
    get { return _alignment }
    set(alignment) {
      guard _alignment != alignment else { return }
      _alignment = alignment
      setNeedsLayout()
    }
  }

  private var _scrollOffset: CGFloat = 0
  open var scrollOffset: CGFloat {
    get { return _scrollOffset }
    set(scrollOffset) {
      if abs(_scrollOffset - scrollOffset) > 0.0001 {
        _scrollOffset = scrollOffset
        _lastUpdateOffset = _scrollOffset - 1 // force refresh
        _scrolling = false // stop scrolling
        updateItemSizeAndCount()
        updateScrollViewDimensions()
        updateLayout()
        let contentOffset: CGPoint
        switch _scrollDirection {
        case .horizontal:
          contentOffset = CGPoint(x: clampedOffset(_scrollOffset) * _itemSize.width, y: 0)
        case .vertical:
          contentOffset = CGPoint(x: 0, y: clampedOffset(_scrollOffset) * _itemSize.height)
        }
        setContentOffsetWithoutEvent(contentOffset)
        didScroll()
      }
    }
  }

  private var _pagingEnabled: Bool = true
  open var isPagingEnabled: Bool {
    get { return _pagingEnabled }
    set(pagingEnabled) {
      guard _pagingEnabled != pagingEnabled else { return }
      _pagingEnabled = pagingEnabled
      _scrollView.isPagingEnabled = _pagingEnabled
      setNeedsLayout()
    }
  }

  /// Default is true
  open var isScrollEnabled: Bool {
    get { return _scrollView.isScrollEnabled }
    set { _scrollView.isScrollEnabled = newValue }
  }

  private var _wrapEnabled: Bool = false
  open var isWrapEnabled: Bool {
    get { return _wrapEnabled }
    set(wrapEnabled) {
      guard _wrapEnabled != wrapEnabled else { return }
      let previousOffset = clampedOffset(_scrollOffset)
      _wrapEnabled = wrapEnabled
      _scrollView.bounces = _bounces && !_wrapEnabled
      setNeedsLayout()
      layoutIfNeeded()
      self.scrollOffset = previousOffset
    }
  }

  /// Default is true
  open var delaysContentTouches: Bool {
    get { return _scrollView.delaysContentTouches }
    set { _scrollView.delaysContentTouches = newValue }
  }

  private var _bounces: Bool = true
  open var bounces: Bool {
    get { return _bounces }
    set(bounces) {
      guard _bounces != bounces else { return }
      _bounces = bounces
      switch _scrollDirection {
      case .horizontal:
        _scrollView.alwaysBounceHorizontal = _bounces
        _scrollView.alwaysBounceVertical = false
      case .vertical:
        _scrollView.alwaysBounceHorizontal = false
        _scrollView.alwaysBounceVertical = _bounces
      }
      _scrollView.bounces = _bounces && !_wrapEnabled
    }
  }

  /// Default is `.normal` (0.998)
  open var decelerationRate: UIScrollView.DecelerationRate {
    get { return _scrollView.decelerationRate }
    set { _scrollView.decelerationRate = newValue }
  }

  private var _autoscroll: CGFloat = 0
  open var autoscroll: CGFloat {
    get { return _autoscroll }
    set(autoscroll) {
      guard abs(_autoscroll - autoscroll) > 0.0001 else { return }
      _autoscroll = autoscroll
      if _autoscroll > 0 {
        startAnimation()
      }
    }
  }

  open var isDragging: Bool {
    return _scrollView.isDragging
  }

  open var isDecelerating: Bool {
    return _scrollView.isDecelerating
  }

  private var _scrolling: Bool = false
  open var isScrolling: Bool {
    return _scrolling
  }

  private var _defersItemViewLoading: Bool = false
  open var defersItemViewLoading: Bool {
    get { return _defersItemViewLoading }
    set { _defersItemViewLoading = newValue }
  }

  private var _scrollDirection: SwipeViewScrollDirection = .horizontal
  open var scrollDirection: SwipeViewScrollDirection {
    get { return _scrollDirection }
    set(scrollDirection) {
      guard _scrollDirection != scrollDirection else { return }
      _scrollDirection = scrollDirection
      switch _scrollDirection {
      case .horizontal:
        _scrollView.alwaysBounceHorizontal = _bounces
        _scrollView.alwaysBounceVertical = false
      case .vertical:
        _scrollView.alwaysBounceHorizontal = false
        _scrollView.alwaysBounceVertical = _bounces
      }
      setNeedsLayout()
    }
  }

  open var isVertical: Bool {
    get { return scrollDirection == .vertical }
    set(vertical) { scrollDirection = vertical ? .vertical : .horizontal }
  }

  // MARK: Initialisation

  private func setUp() {
    _scrollView = UIScrollView(frame: bounds)
    _scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    _scrollView.autoresizesSubviews = true
    _scrollView.delegate = self
    _scrollView.bounces = _bounces && !_wrapEnabled
    switch _scrollDirection {
    case .horizontal:
      _scrollView.alwaysBounceHorizontal = _bounces
      _scrollView.alwaysBounceVertical = false
    case .vertical:
      _scrollView.alwaysBounceHorizontal = false
      _scrollView.alwaysBounceVertical = _bounces
    }
    _scrollView.isPagingEnabled = _pagingEnabled
    _scrollView.showsHorizontalScrollIndicator = false
    _scrollView.showsVerticalScrollIndicator = false
    _scrollView.scrollsToTop = false
    _scrollView.clipsToBounds = false

    _previousContentOffset = _scrollView.contentOffset

    let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap(_:)))
    tapGesture.delegate = self
    _scrollView.addGestureRecognizer(tapGesture)

    clipsToBounds = true

    // place scrollview at bottom of hierarchy
    insertSubview(_scrollView, at: 0)

    if dataSource != nil {
      reloadData()
    }
  }

  public required init?(coder: NSCoder) {
    super.init(coder: coder)
    setUp()
  }

  public override init(frame: CGRect = .zero) {
    super.init(frame: frame)
    setUp()
  }

  deinit {
    _timer?.invalidate()
  }

  // MARK: View layout

  private func updateScrollOffset() {
    if _wrapEnabled {
      let itemsWide = _numberOfItems == 1 ? 1 : 3
      switch _scrollDirection {
      case .horizontal:
        let scrollWidth = _scrollView.contentSize.width / CGFloat(itemsWide)
        if _scrollView.contentOffset.x < scrollWidth {
          _previousContentOffset.x += scrollWidth
          setContentOffsetWithoutEvent(CGPoint(x: _scrollView.contentOffset.x + scrollWidth, y: 0))
        } else if _scrollView.contentOffset.x >= scrollWidth * 2 {
          _previousContentOffset.x -= scrollWidth
          setContentOffsetWithoutEvent(CGPoint(x: _scrollView.contentOffset.x - scrollWidth, y: 0))
        }
        _scrollOffset = clampedOffset(_scrollOffset)
      case .vertical:
        let scrollHeight = _scrollView.contentSize.height / CGFloat(itemsWide)
        if _scrollView.contentOffset.y < scrollHeight {
          _previousContentOffset.y += scrollHeight
          setContentOffsetWithoutEvent(CGPoint(x: 0, y: _scrollView.contentOffset.y + scrollHeight))
        } else if _scrollView.contentOffset.y >= scrollHeight * 2 {
          _previousContentOffset.y -= scrollHeight
          setContentOffsetWithoutEvent(CGPoint(x: 0, y: _scrollView.contentOffset.y - scrollHeight))
        }
        _scrollOffset = clampedOffset(_scrollOffset)
      }
    }
    switch _scrollDirection {
    case .horizontal:
      if abs(_scrollView.contentOffset.y) > 0.0001 {
        setContentOffsetWithoutEvent(CGPoint(x: _scrollView.contentOffset.x, y: 0))
      }
    case .vertical:
      if abs(_scrollView.contentOffset.x) > 0.0001 {
        setContentOffsetWithoutEvent(CGPoint(x: 0, y: _scrollView.contentOffset.y))
      }
    }
  }

  private func updateScrollViewDimensions() {
    var frame = bounds
    var contentSize = frame.size

    switch _scrollDirection {
    case .horizontal:
      contentSize.height -= _scrollView.contentInset.top + _scrollView.contentInset.bottom
    case .vertical:
      contentSize.width -= _scrollView.contentInset.left + _scrollView.contentInset.right
    }

    switch _alignment {
    case .center:
      switch _scrollDirection {
      case .horizontal:
        frame = CGRect(
          x: (bounds.size.width - _itemSize.width * CGFloat(_itemsPerPage)) / 2,
          y: 0,
          width: _itemSize.width * CGFloat(_itemsPerPage),
          height: bounds.size.height
        )
        contentSize.width = _itemSize.width * CGFloat(_numberOfItems)
      case .vertical:
        frame = CGRect(
          x: 0,
          y: (bounds.size.height - _itemSize.height * CGFloat(_itemsPerPage)) / 2,
          width: bounds.size.width,
          height: _itemSize.height * CGFloat(_itemsPerPage)
        )
        contentSize.height = _itemSize.height * CGFloat(_numberOfItems)
      }

    case .edge:
      switch _scrollDirection {
      case .horizontal:
        frame = CGRect(x: 0, y: 0, width: _itemSize.width * CGFloat(_itemsPerPage), height: bounds.size.height)
        contentSize.width = _itemSize.width * CGFloat(_numberOfItems) - (bounds.size.width - frame.size.width)
      case .vertical:
        frame = CGRect(x: 0, y: 0, width: bounds.size.width, height: _itemSize.height * CGFloat(_itemsPerPage))
        contentSize.height = _itemSize.height * CGFloat(_numberOfItems) - (bounds.size.height - frame.size.height)
      }
    }

    if _wrapEnabled {
      let itemsWide = _numberOfItems == 1 ? 1 : _numberOfItems * 3
      switch _scrollDirection {
      case .horizontal:
        contentSize.width = _itemSize.width * CGFloat(itemsWide)
      case .vertical:
        contentSize.height = _itemSize.height * CGFloat(itemsWide)
      }
    } else if _pagingEnabled && !_truncateFinalPage {
      switch _scrollDirection {
      case .horizontal:
        contentSize.width = ceil(contentSize.width / frame.size.width) * frame.size.width
      case .vertical:
        contentSize.height = ceil(contentSize.height / frame.size.height) * frame.size.height
      }
    }

    if _scrollView.frame != frame {
      _scrollView.frame = frame
    }

    if _scrollView.contentSize != contentSize {
      _scrollView.contentSize = contentSize
    }
  }

  private func offsetForItem(at index: Int) -> CGFloat {
    // calculate relative position
    var offset = CGFloat(index) - _scrollOffset
    let _numberOfItems = CGFloat(_numberOfItems)
    if _wrapEnabled {
      switch _alignment {
      case .center:
        if offset > _numberOfItems / 2 {
          offset -= _numberOfItems
        } else if offset < -_numberOfItems / 2 {
          offset += _numberOfItems
        }
      case .edge:
        let width: CGFloat
        let x: CGFloat
        let itemWidth: CGFloat
        switch _scrollDirection {
        case .horizontal:
          width = bounds.size.width
          x = _scrollView.frame.origin.x
          itemWidth = _itemSize.width
        case .vertical:
          width = bounds.size.height
          x = _scrollView.frame.origin.y
          itemWidth = _itemSize.height
        }
        if offset * itemWidth + x > width {
          offset -= _numberOfItems
        } else if offset * itemWidth + x < -itemWidth {
          offset += _numberOfItems
        }
      }
    }
    return offset
  }

  private func setFrame(for view: UIView, at index: Int) {
    if window != nil {
      var center = view.center
      switch _scrollDirection {
      case .horizontal:
        center.x = (offsetForItem(at: index) + 0.5) * _itemSize.width + _scrollView.contentOffset.x
      case .vertical:
        center.y = (offsetForItem(at: index) + 0.5) * _itemSize.height + _scrollView.contentOffset.y
      }

      let disableAnimation = center != view.center
      let animationEnabled = UIView.areAnimationsEnabled
      if disableAnimation && animationEnabled {
        UIView.setAnimationsEnabled(false)
      }

      switch _scrollDirection {
      case .horizontal:
        view.center = CGPoint(x: center.x, y: _scrollView.frame.size.height/2)
      case .vertical:
        view.center = CGPoint(x: _scrollView.frame.size.width/2, y: center.y)
      }

      view.bounds = CGRect(x: 0, y: 0, width: _itemSize.width, height: _itemSize.height)

      if disableAnimation && animationEnabled {
        UIView.setAnimationsEnabled(true)
      }
    }
  }

  private func layoutItemViews() {
    for view in self.visibleItemViews {
      if let index = indexOfItemView(view) {
        setFrame(for: view, at: index)
      }
    }
  }

  private func updateLayout() {
    updateScrollOffset()
    loadUnloadViews()
    layoutItemViews()
  }

  open override func layoutSubviews() {
    super.layoutSubviews()

    updateItemSizeAndCount()
    updateScrollViewDimensions()
    updateLayout()
    if _pagingEnabled && !_scrolling {
      scrollToItem(at: self.currentItemIndex, duration: 0.25)
    }
  }

  // MARK: View queing

  private func queueItemView(_ view: UIView?) {
    if let view {
      _itemViewPool.insert(view)
    }
  }

  private func dequeueItemView() -> UIView? {
    let view = _itemViewPool.first
    if let view {
      _itemViewPool.remove(view)
    }
    return view
  }

  // MARK: Scrolling

  private func didScroll() {
    // handle wrap
    updateScrollOffset()

    // update view
    layoutItemViews()
    _delegate?.swipeViewDidScroll?(self)

    if !_defersItemViewLoading || abs(minScrollDistance(fromOffset: _lastUpdateOffset, toOffset:_scrollOffset)) >= 1 {
      // update item index
      _currentItemIndex = clampedIndex(Int(round(_scrollOffset)))

      // load views
      _lastUpdateOffset = CGFloat(_currentItemIndex)
      loadUnloadViews()

      // send index update event
      if _previousItemIndex != _currentItemIndex {
        _previousItemIndex = _currentItemIndex
        _delegate?.swipeViewCurrentItemIndexDidChange?(self)
      }
    }
  }

  private func easeInOut(_ time: TimeInterval) -> CGFloat {
    return time < 0.5 ? 0.5 * pow(time * 2, 3) : 0.5 * pow(time * 2 - 2, 3) + 1
  }

  @objc private func step() {
    let currentTime = CFAbsoluteTimeGetCurrent()
    var delta = _lastTime - currentTime
    _lastTime = currentTime

    if _scrolling {
      let time = min(1, (currentTime - _startTime) / _scrollDuration)
      delta = easeInOut(time)
      _scrollOffset = clampedOffset(_startOffset + (_endOffset - _startOffset) * delta)
      switch _scrollDirection {
      case .horizontal:
        setContentOffsetWithoutEvent(CGPoint(x: _scrollOffset * _itemSize.width, y: 0))
      case .vertical:
        setContentOffsetWithoutEvent(CGPoint(x: 0, y: _scrollOffset * _itemSize.height))
      }
      didScroll()
      if time == 1 {
        _scrolling = false
        didScroll()
        _delegate?.swipeViewDidEndScrollingAnimation?(self)
      }
    } else if _autoscroll > 0 {
      if !_scrollView.isDragging {
        self.scrollOffset = clampedOffset(_scrollOffset + delta * _autoscroll)
      }
    } else {
      stopAnimation()
    }
  }

  private func startAnimation() {
    if _timer == nil {
      _timer = Timer(timeInterval: 1/60, target: self, selector: #selector(step), userInfo: nil, repeats: true)
      RunLoop.main.add(_timer, forMode: .default)
      RunLoop.main.add(_timer, forMode: .tracking)
    }
  }

  private func stopAnimation() {
    _timer?.invalidate()
    _timer = nil
  }

  private func clampedIndex(_ index: Int) -> Int {
    if _wrapEnabled {
      return _numberOfItems > 0 ? (index - Int(floor(CGFloat(index) / CGFloat(_numberOfItems))) * _numberOfItems) : 0
    } else {
      return min(max(0, index), max(0, _numberOfItems - 1))
    }
  }

  private func clampedOffset(_ offset: CGFloat) -> CGFloat {
    var returnValue: CGFloat = 0
    if _wrapEnabled {
      returnValue = _numberOfItems > 0 ? (offset - floor(offset / CGFloat(_numberOfItems)) * CGFloat(_numberOfItems)) : 0
    } else {
      returnValue = min(max(0, offset), max(0, CGFloat(_numberOfItems) - 1))
    }
    return returnValue
  }

  private func setContentOffsetWithoutEvent(_ contentOffset: CGPoint) {
    if _scrollView.contentOffset != contentOffset {
      let animationEnabled = UIView.areAnimationsEnabled
      if animationEnabled {
        UIView.setAnimationsEnabled(false)
      }
      _suppressScrollEvent = true
      _scrollView.contentOffset = contentOffset
      _suppressScrollEvent = false
      if animationEnabled {
        UIView.setAnimationsEnabled(true)
      }
    }
  }

  private func minScrollDistance(fromIndex: Int, toIndex: Int) -> Int {
    let directDistance = toIndex - fromIndex
    if _wrapEnabled {
      var wrappedDistance = min(toIndex, fromIndex) + _numberOfItems - max(toIndex, fromIndex)
      if fromIndex < toIndex {
        wrappedDistance = -wrappedDistance
      }
      return abs(directDistance) <= abs(wrappedDistance) ? directDistance : wrappedDistance
    }
    return directDistance
  }

  private func minScrollDistance(fromOffset: CGFloat, toOffset: CGFloat) -> CGFloat {
    let directDistance = toOffset - fromOffset
    if _wrapEnabled {
      var wrappedDistance = min(toOffset, fromOffset) + CGFloat(_numberOfItems) - max(toOffset, fromOffset)
      if fromOffset < toOffset {
        wrappedDistance = -wrappedDistance
      }
      return abs(directDistance) <= abs(wrappedDistance) ? directDistance : wrappedDistance
    }
    return directDistance
  }

  open func scrollByOffset(_ offset: CGFloat, duration: TimeInterval) {
    if duration > 0 {
      _scrolling = true
      _startTime = Date().timeIntervalSinceReferenceDate
      _startOffset = _scrollOffset
      _scrollDuration = duration
      _endOffset = _startOffset + offset
      if !_wrapEnabled {
        _endOffset = clampedOffset(_endOffset)
      }
      startAnimation()
    } else {
      self.scrollOffset += offset
    }
  }

  open func scrollToOffset(_ offset: CGFloat, duration: TimeInterval) {
    scrollByOffset(minScrollDistance(fromOffset: _scrollOffset, toOffset: offset), duration: duration)
  }

  open func scrollByNumberOfItems(_ itemCount: Int, duration: TimeInterval) {
    if duration > 0 {
      var offset: CGFloat = 0
      if itemCount > 0 {
        offset = (floor(_scrollOffset) + CGFloat(itemCount)) - _scrollOffset
      } else if itemCount < 0 {
        offset = (ceil(_scrollOffset) + CGFloat(itemCount)) - _scrollOffset
      } else {
        offset = round(_scrollOffset) - _scrollOffset
      }
      scrollByOffset(offset, duration: duration)
    } else {
      self.scrollOffset = CGFloat(clampedIndex(_previousItemIndex + itemCount))
    }
  }

  open func scrollToItem(at index: Int, duration: TimeInterval) {
    scrollToOffset(CGFloat(index), duration: duration)
  }

  open func scrollToPage(_ page: Int, duration: TimeInterval) {
    var index = page * _itemsPerPage
    if _truncateFinalPage {
      index = min(index, _numberOfItems - _itemsPerPage)
    }
    scrollToItem(at: index, duration: duration)
  }

  // MARK: View loading

  @discardableResult
  private func loadView(at index: Int) -> UIView {
    let view = _dataSource?.swipeView(self, viewForItemAt: index, reusing: dequeueItemView()) ?? UIView()

    if let oldView = itemView(at: index) {
      queueItemView(oldView)
      oldView.removeFromSuperview()
    }

    _itemViews[index] = view
    setFrame(for: view, at: index)
    view.isUserInteractionEnabled = true
    _scrollView.addSubview(view)

    return view
  }

  private func updateItemSizeAndCount() {
    // get number of items
    _numberOfItems = _dataSource?.numberOfItems(in: self) ?? 0

    // get item size
    let size = _delegate?.swipeViewItemSize?(self) ?? .zero
    if size != .zero {
      _itemSize = size
    } else if _numberOfItems > 0 {
      let view = visibleItemViews.last ?? _dataSource?.swipeView(self, viewForItemAt: 0, reusing: dequeueItemView())
      _itemSize = view?.frame.size ?? .zero
    }

    // prevent crashes
    if _itemSize.width < 0.0001 {
      _itemSize.width = 1
    }
    if _itemSize.height < 0.0001 {
      _itemSize.height = 1
    }
  }

  private func loadUnloadViews() {
    // check that item size is known
    let itemWidth: CGFloat
    switch _scrollDirection {
    case .horizontal:
      itemWidth = _itemSize.width
    case .vertical:
      itemWidth = _itemSize.height
    }
    if itemWidth > 0 {
      // calculate offset and bounds
      let width: CGFloat
      let x: CGFloat
      switch _scrollDirection {
      case .horizontal:
        width = bounds.size.width
        x = _scrollView.frame.origin.x
      case .vertical:
        width = bounds.size.height
        x = _scrollView.frame.origin.y
      }

      // calculate range
      let startOffset = clampedOffset(_scrollOffset - x / itemWidth)
      var startIndex = Int(floor(startOffset))
      var numberOfVisibleItems = Int(ceil(width / itemWidth + (startOffset - CGFloat(startIndex))))
      if _defersItemViewLoading {
        startIndex = _currentItemIndex - Int(ceil(x / itemWidth)) - 1
        numberOfVisibleItems = Int(ceil(width / itemWidth)) + 3
      }

      // create indices
      numberOfVisibleItems = min(numberOfVisibleItems, _numberOfItems)
      var visibleIndices = Set<Int>(minimumCapacity: numberOfVisibleItems)
      for i in 0..<numberOfVisibleItems {
        let index = clampedIndex(i + startIndex)
        visibleIndices.insert(index)
      }

      // remove offscreen views
      for number in _itemViews.keys {
        if !visibleIndices.contains(number) {
          if let view = _itemViews[number] {
            queueItemView(view)
            view.removeFromSuperview()
            _itemViews[number] = nil
          }
        }
      }

      // add onscreen views
      for number in visibleIndices {
        let view = _itemViews[number]
        if view == nil {
          loadView(at: number)
        }
      }
    }
  }

  open func reloadItem(at index: Int) {
    // if view is visible
    if itemView(at: index) != nil {
      // reload view
      loadView(at: index)
    }
  }

  open func reloadData() {
    // remove old views
    for view in self.visibleItemViews {
      view.removeFromSuperview()
    }

    // reset view pools
    _itemViews.removeAll()
    _itemViewPool.removeAll()

    // get number of items
    updateItemSizeAndCount()

    // layout views
    setNeedsLayout()

    // fix scroll offset
    if _numberOfItems > 0 && _scrollOffset < 0 {
      self.scrollOffset = 0
    }
  }

  open override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let view = super.hitTest(point, with: event)
    if view == self {
      for subview in _scrollView.subviews {
        let offset = CGPoint(
          x: point.x - _scrollView.frame.origin.x + _scrollView.contentOffset.x - subview.frame.origin.x,
          y: point.y - _scrollView.frame.origin.y + _scrollView.contentOffset.y - subview.frame.origin.y
        )

        if let view = subview.hitTest(offset, with: event) {
          return view
        }
      }
      return _scrollView
    }
    return view
  }

  open override func didMoveToSuperview() {
    if superview != nil {
      setNeedsLayout()
      if _scrolling {
        startAnimation()
      }
    } else {
      stopAnimation()
    }
  }

  // MARK: Gestures and taps

  private func viewOrSuperviewIndex(_ view: UIView?) -> Int? {
    guard let view, view != _scrollView else {
      return nil
    }
    if let index = indexOfItemView(view) {
      return index
    }
    return viewOrSuperviewIndex(view.superview)
  }

  private func viewOrSuperviewHandlesTouches(_ view: UIView?) -> Bool {
    // thanks to @mattjgalloway and @shaps for idea
    // https://gist.github.com/mattjgalloway/6279363
    // https://gist.github.com/shaps80/6279008

    guard let view else { return false }
//    Class class = [view class];
//    while (class && class != [UIView class])
//    {
//      unsigned int numberOfMethods;
//      Method *methods = class_copyMethodList(class, &numberOfMethods);
//      for (unsigned int i = 0; i < numberOfMethods; i++)
//      {
//        if (method_getName(methods[i]) == @selector(touchesBegan:withEvent:))
//        {
//          free(methods);
//          return YES;
//        }
//      }
//      if (methods) free(methods);
//      class = [class superclass];
//    }
//
    if let superview = view.superview, superview != _scrollView {
      return viewOrSuperviewHandlesTouches(superview)
    }

    return false
  }

  open func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    if gestureRecognizer is UITapGestureRecognizer {
      // handle tap
      if let index = viewOrSuperviewIndex(touch.view) {
        if _delegate?.swipeView?(self, shouldSelectItemAt: index) ?? true || viewOrSuperviewHandlesTouches(touch.view) {
          return false
        } else {
          return true
        }
      }
    }
    return false
  }

  @objc private func didTap(_ tapGesture: UITapGestureRecognizer) {
    let point = tapGesture.location(in: _scrollView)
    var index: Int
    switch _scrollDirection {
    case .horizontal:
      index = Int(point.x / _itemSize.width)
    case .vertical:
      index = Int(point.y / _itemSize.height)
    }
    if _wrapEnabled {
      index = index % _numberOfItems
    }
    if index >= 0 && index < _numberOfItems {
      delegate?.swipeView?(self, didSelectItemAt: index)
    }
  }

  // MARK: UIScrollViewDelegate methods

  open func scrollViewDidScroll(_ scrollView: UIScrollView) {
    if !_suppressScrollEvent {
      // stop scrolling animation
      _scrolling = false

      // update scrollOffset
      switch _scrollDirection {
      case .horizontal:
        let delta = _scrollView.contentOffset.x - _previousContentOffset.x
        _previousContentOffset = _scrollView.contentOffset
        _scrollOffset += delta / _itemSize.width
      case .vertical:
        let delta = _scrollView.contentOffset.y - _previousContentOffset.y
        _previousContentOffset = _scrollView.contentOffset
        _scrollOffset += delta / _itemSize.height
      }

      // update view and call delegate
      didScroll()
    } else {
      _previousContentOffset = _scrollView.contentOffset
    }
  }

  open func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    _delegate?.swipeViewWillBeginDragging?(self)

    // force refresh
    _lastUpdateOffset = self.scrollOffset - 1
    didScroll()
  }

  open func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
    if !decelerate {
      // force refresh
      _lastUpdateOffset = self.scrollOffset - 1
      didScroll()
    }
    _delegate?.swipeViewDidEndDragging?(self, willDecelerate: decelerate)
  }

  open func scrollViewWillBeginDecelerating(_ scrollView: UIScrollView) {
    _delegate?.swipeViewWillBeginDecelerating?(self)
  }

  open func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
    // prevent rounding errors from accumulating
    let integerOffset = round(_scrollOffset)
    if abs(_scrollOffset - integerOffset) < 0.01 {
      _scrollOffset = integerOffset
    }

    // force refresh
    _lastUpdateOffset = self.scrollOffset - 1
    didScroll()

    _delegate?.swipeViewDidEndDecelerating?(self)
  }
}
