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
  private var _suppressScrollEvent: Bool
  private var _scrollDuration: TimeInterval
  private var _startTime: TimeInterval
  private var _lastTime: TimeInterval
  private var _startOffset: CGFloat
  private var _endOffset: CGFloat
  private var _lastUpdateOffset: CGFloat
  private var _timer: Timer?

  private var _dataSource: SwipeViewDataSource?
  @IBOutlet open weak var dataSource: SwipeViewDataSource? {
    get { return _dataSource }
    set { _dataSource = newValue }
  }

  private var _delegate: SwipeViewDelegate?
  @IBOutlet open weak var delegate: SwipeViewDelegate? {
    get { return _delegate }
    set { _delegate = newValue }
  }

  private var _numberOfItems: Int = 0
  open var numberOfItems: Int {
    return _numberOfItems
  }

  private var _numberOfPages: Int = 0
  open var numberOfPages: Int {
    return _numberOfPages
  }

  private var _itemSize: CGSize = .zero
  open var itemSize: CGSize {
    return _itemSize
  }

  private var _itemsPerPage: Int = 1
  open var itemsPerPage: Int {
    get { return _itemsPerPage }
    set { _itemsPerPage = newValue }
  }

  private var _truncateFinalPage: Bool = false
  open var truncateFinalPage: Bool {
    get { return _truncateFinalPage }
    set { _truncateFinalPage = newValue }
  }

  // MARK: View management

  open var indexesForVisibleItems: [Int] {
    return []
  }

  open var visibleItemViews: [UIView] {
    return []
  }

  open var currentItemView: UIView? {
    return nil
  }

  private var _currentItemIndex: Int = 0
  open var currentItemIndex: Int {
    get { return _currentItemIndex }
    set { _currentItemIndex = newValue }
  }

  private var _currentPage: Int = 0
  open var currentPage: Int {
    get { return _currentPage }
    set { _currentPage = newValue }
  }

  private var _alignment: SwipeViewAlignment = .center
  open var alignment: SwipeViewAlignment {
    get { return _alignment }
    set { _alignment = newValue }
  }

  private var _scrollOffset: CGFloat = 0
  open var scrollOffset: CGFloat {
    get { return _scrollOffset }
    set { _scrollOffset = newValue }
  }

  private var _pagingEnabled: Bool = true
  open var isPagingEnabled: Bool {
    get { return _pagingEnabled }
    set { _pagingEnabled = newValue }
  }

  private var _scrollEnabled: Bool = true
  open var isScrollEnabled: Bool {
    get { return _scrollEnabled }
    set { _scrollEnabled = newValue }
  }

  private var _wrapEnabled: Bool = false
  open var isWrapEnabled: Bool {
    get { return _wrapEnabled }
    set { _wrapEnabled = newValue }
  }

  private var _delaysContentTouches: Bool = true
  open var delaysContentTouches: Bool {
    get { return _delaysContentTouches }
    set { _delaysContentTouches = newValue }
  }

  private var _bounces: Bool = true
  open var bounces: Bool {
    get { return _bounces }
    set { _bounces = newValue }
  }

  private var _decelerationRate: CGFloat = 0
  open var decelerationRate: CGFloat {
    get { return _decelerationRate }
    set { _decelerationRate = newValue }
  }

  private var _autoscroll: CGFloat = 0
  open var autoscroll: CGFloat {
    get { return _autoscroll }
    set { _autoscroll = newValue }
  }

  private var _dragging: Bool = false
  open var isDragging: Bool {
    return _dragging
  }

  private var _decelerating: Bool = false
  open var isDecelerating: Bool {
    return _decelerating
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

  private var _vertical: Bool = false
  open var isVertical: Bool {
    get { return _vertical }
    set { _vertical = newValue }
  }

  // MARK: Initialisation

  private func setUp() {
    _scrollView = UIScrollView()
    _scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    _scrollView.autoresizesSubviews = true
    _scrollView.delegate = self
    _scrollView.delaysContentTouches = _delaysContentTouches
    _scrollView.bounces = _bounces && !_wrapEnabled
    _scrollView.alwaysBounceHorizontal = !_vertical && _bounces
    _scrollView.alwaysBounceVertical = _vertical && _bounces
    _scrollView.isPagingEnabled = _pagingEnabled
    _scrollView.isScrollEnabled = _scrollEnabled
    _scrollView.decelerationRate = .init(rawValue: _decelerationRate)
    _scrollView.showsHorizontalScrollIndicator = false
    _scrollView.showsVerticalScrollIndicator = false
    _scrollView.scrollsToTop = false
    _scrollView.clipsToBounds = false

    _decelerationRate = _scrollView.decelerationRate.rawValue
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
    timer?.invalidate()
  }
}
