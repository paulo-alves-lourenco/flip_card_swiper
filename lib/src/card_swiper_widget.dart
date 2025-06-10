import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:async';

/// A customizable swipeable card widget with animations and gesture support.
/// Allows cards to be swiped with horizontal drag gestures, providing haptic feedback
/// and smooth animations for card transitions.
class FlipCardSwiper<T> extends StatefulWidget {
  /// The list of data used to build the cards.
  final List<T> cardData;

  /// The duration of the card swipe animation.
  final Duration animationDuration;

  /// The duration of the rightward drag animation.
  final Duration rightDragDuration;

  /// The duration of the card collection animation.
  final Duration collectionDuration;

  /// The maximum distance for a drag gesture to trigger animations.
  final double maxDragDistance;

  /// The limit for dragging right before animation blocks further motion.
  final double dragRightLimit;

  /// The threshold value for determining whether to complete the swipe animation.
  final double thresholdValue;

  /// A callback triggered when the top card changes.
  final void Function(int)? onCardChange;

  /// A builder function to create each card widget.
  /// - `context`: The build context.
  /// - `index`: The index of the card in the data.
  /// - `visibleIndex`: The index of the card in the visible stack (0 = top).
  final Widget Function(BuildContext context, int index, int visibleIndex)
      cardBuilder;

  /// Whether the card collection animation should start automatically.
  final bool shouldStartCardCollectionAnimation;

  /// A callback triggered when the card collection animation is complete.
  final void Function(bool value) onCardCollectionAnimationComplete;

  // Offset and scale parameters for the top card.
  final double topCardOffsetStart;
  final double topCardOffsetEnd;
  final double topCardScaleStart;
  final double topCardScaleEnd;

  // Offset and scale parameters for the second card.
  final double secondCardOffsetStart;
  final double secondCardOffsetEnd;
  final double secondCardScaleStart;
  final double secondCardScaleEnd;

  // Offset and scale parameters for the third card.
  final double thirdCardOffsetStart;
  final double thirdCardOffsetEnd;
  final double thirdCardScaleStart;
  final double thirdCardScaleEnd;

  /// Creates a FlipCardSwiper widget.
  const FlipCardSwiper({
    required this.cardData,
    required this.cardBuilder,
    this.animationDuration = const Duration(milliseconds: 800),
    this.rightDragDuration = const Duration(milliseconds: 300),
    this.collectionDuration = const Duration(milliseconds: 1000),
    this.maxDragDistance = 220.0,
    this.dragRightLimit = -40.0,
    this.thresholdValue = 0.3,
    this.onCardChange,
    this.topCardOffsetStart = 0.0,
    this.topCardOffsetEnd = -15.0,
    this.topCardScaleStart = 1.0,
    this.topCardScaleEnd = 0.9,
    this.secondCardOffsetStart = -15.0,
    this.secondCardOffsetEnd = 0.0,
    this.secondCardScaleStart = 0.95,
    this.secondCardScaleEnd = 1.0,
    this.thirdCardOffsetStart = -30.0,
    this.thirdCardOffsetEnd = -15.0,
    this.thirdCardScaleStart = 0.9,
    this.thirdCardScaleEnd = 0.95,
    this.shouldStartCardCollectionAnimation = false,
    required this.onCardCollectionAnimationComplete,
    super.key,
  });

  @override
  State<FlipCardSwiper<T>> createState() => _FlipCardSwiperState<T>();
}

class _FlipCardSwiperState<T> extends State<FlipCardSwiper<T>>
    with TickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _xOffsetAnimation;
  Animation<double>? _rotationAnimation;
  Animation<double>? _animation;
  AnimationController? _rightDragController;
  Animation<double>? _rightDragAnimation;
  AnimationController? _cardCollectionAnimationController;
  Animation<double>? _cardCollectionXOffsetAnimation;

  double _startAnimationValue = 0.0;
  double _dragStartPosition = 0.0;
  double _dragOffset = 0.0;
  bool _isCardSwitched = false;
  bool _hasReachedHalf = false;
  bool _isAnimationBlocked = false;
  bool _shouldPlayVibration = true;

  late List<T> _cardData;

  Timer? _debounceTimer;

  Widget? _topCardWidget;
  int? _topCardIndex;

  Widget? _secondCardWidget;
  int? _secondCardIndex;

  Widget? _thirdCardWidget;
  int? _thirdCardIndex;

  Widget? _poppedCardWidget;
  int? _poppedCardIndex;

  /// Triggers haptic feedback when a card is successfully switched.
  Future<void> onCardSwitchVibration() async {
    HapticFeedback.lightImpact();
    Future.delayed(const Duration(milliseconds: 250), () {
      HapticFeedback.selectionClick();
    });
  }

  /// Triggers haptic feedback when dragging down is blocked.
  Future<void> onCardBlockVibration() async {
    HapticFeedback.lightImpact();
    Future.delayed(const Duration(milliseconds: 100), () {
      HapticFeedback.lightImpact();
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      HapticFeedback.mediumImpact();
    });
  }

  @override
  void initState() {
    super.initState();

    // Copy the card data to allow modifications.
    _cardData = List.from(widget.cardData);

    // Initialize the animation controller for swipe animation.
    _controller = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );

    // Create a curved animation for the swipe.
    _animation = CurvedAnimation(
      parent: _controller ?? AnimationController(vsync: this),
      curve: Curves.easeInOut,
    );

    // Define the xOffset animation using TweenSequence.
    _xOffsetAnimation = TweenSequence<double>([
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0.0, end: 0.5),
        weight: 45.0,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0.5, end: 0.0),
        weight: 55.0,
      ),
    ]).animate(_animation ?? const AlwaysStoppedAnimation(0.0));

    // Define the rotation animation from 0 to -180 degrees.
    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 180.0,
    ).animate(_animation ?? const AlwaysStoppedAnimation(0.0));

    // Initialize the rightward drag controller.
    _rightDragController = AnimationController(
      duration: widget.rightDragDuration,
      vsync: this,
    );

    _rightDragAnimation = Tween<double>(
      begin: 0.0,
      end: 0.0,
    ).animate(_rightDragController ?? AnimationController(vsync: this))
      ..addListener(() {
        _dragOffset = _rightDragAnimation?.value ?? 0.0;
      });

    // Listen to the animation value to switch cards at the midpoint (0.5).
    _controller?.addListener(() {
      if (_cardData.length > 1) {
        if (!_isCardSwitched && (_controller?.value ?? 0.0) >= 0.5) {
          if (_debounceTimer?.isActive ?? false) {
            _isCardSwitched = true;
            return;
          }

          // Move the top card to the back of the stack.
          var firstCard = _cardData.removeAt(0);
          _poppedCardIndex = widget.cardData.indexOf(firstCard);
          _poppedCardWidget =
              widget.cardBuilder(context, _poppedCardIndex ?? 0, -1);
          _cardData.add(firstCard);
          onCardSwitchVibration();

          _isCardSwitched = true;

          _updateCardWidgets();

          // Trigger the callback with the new top card index.
          if (widget.onCardChange != null) {
            widget.onCardChange?.call(widget.cardData.indexOf(_cardData[0]));
          }

          _debounceTimer = Timer(const Duration(milliseconds: 300), () {});
        }

        // Reset the switch flag when the animation resets.
        if ((_controller?.value ?? 0.0) == 1.0) {
          _isCardSwitched = false;
          _controller?.reset();
          _hasReachedHalf = false;
        }
      } else {
        // Reset the animation if there is only one card.
        _controller?.reset();
      }
    });

    // Start the card collection animation if enabled.
    if (widget.shouldStartCardCollectionAnimation) {
      _cardCollectionAnimationController = AnimationController(
        duration: widget.collectionDuration,
        vsync: this,
      );

      _cardCollectionXOffsetAnimation = Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(CurvedAnimation(
        parent: _cardCollectionAnimationController ??
            AnimationController(vsync: this),
        curve: Curves.easeOutCubic,
      ));

      _cardCollectionAnimationController
          ?.forward()
          .then((_) => widget.onCardCollectionAnimationComplete(false));
    }

    _updateCardWidgets();
  }

  /// Updates the widgets for the top three visible cards.
  void _updateCardWidgets() {
    if (_cardData.isNotEmpty) {
      _topCardIndex = widget.cardData.indexOf(_cardData[0]);
      _topCardWidget = widget.cardBuilder(context, _topCardIndex ?? 0, 0);
    } else {
      _topCardIndex = null;
      _topCardWidget = null;
    }

    if (_cardData.length > 1) {
      _secondCardIndex = widget.cardData.indexOf(_cardData[1]);
      _secondCardWidget = widget.cardBuilder(context, _secondCardIndex ?? 0, 1);
    } else {
      _secondCardIndex = null;
      _secondCardWidget = null;
    }

    if (_cardData.length > 2) {
      _thirdCardIndex = widget.cardData.indexOf(_cardData[2]);
      _thirdCardWidget = widget.cardBuilder(context, _thirdCardIndex ?? 0, 2);
    } else {
      _thirdCardIndex = null;
      _thirdCardWidget = null;
    }
  }

  @override
  void didUpdateWidget(FlipCardSwiper<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.cardData != oldWidget.cardData) {
      _controller?.stop();
      _rightDragController?.stop();

      _cardData = List.from(widget.cardData);
      _isCardSwitched = false;
      _hasReachedHalf = false;
      _startAnimationValue = 0.0;
      _dragStartPosition = 0.0;
      _dragOffset = 0.0;

      _controller?.reset();
      _rightDragController?.reset();

      _updateCardWidgets();
    }

    if (widget.shouldStartCardCollectionAnimation !=
        oldWidget.shouldStartCardCollectionAnimation) {
      if (widget.shouldStartCardCollectionAnimation) {
        _cardCollectionAnimationController = AnimationController(
          duration: const Duration(milliseconds: 1000),
          vsync: this,
        );

        _cardCollectionXOffsetAnimation = Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).animate(CurvedAnimation(
          parent: _cardCollectionAnimationController ??
              AnimationController(vsync: this),
          curve: Curves.easeOutCubic,
        ));

        _cardCollectionAnimationController
            ?.forward()
            .then((_) => widget.onCardCollectionAnimationComplete(false));
      } else {
        _cardCollectionAnimationController?.dispose();
        _cardCollectionAnimationController = null;
        _cardCollectionXOffsetAnimation = null;
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _rightDragController?.dispose();
    _debounceTimer?.cancel();
    _cardCollectionAnimationController?.dispose();
    super.dispose();
  }

  // Handle the start of the horizontal drag
  void _onHorizontalDragStart(DragStartDetails details) {
    if (_controller?.isAnimating == true ||
        _rightDragController?.isAnimating == true ||
        widget.shouldStartCardCollectionAnimation ||
        _cardData.length == 1) {
      // Do not process the gesture if animating or if there's only one card
      return;
    }
    _isAnimationBlocked = false;
    _startAnimationValue = _controller?.value ?? 0.0;
    _dragStartPosition = details.globalPosition.dx;
    _controller?.stop(canceled: false);
    _rightDragController?.stop();
    _hasReachedHalf = false;
  }

  // Update the animation value based on the drag
  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_controller?.isAnimating == true ||
        _rightDragController?.isAnimating == true ||
        _hasReachedHalf ||
        widget.shouldStartCardCollectionAnimation ||
        _isAnimationBlocked ||
        _cardData.length == 1) {
      // Do not process the gesture if animating or if the card has reached half or if there's only one card
      return;
    }
    if (_hasReachedHalf) {
      // Stop responding to drag updates
      return;
    }

    double dragDistance = _dragStartPosition -
        details.globalPosition.dx; // Positive when dragging left

    if (dragDistance >= 0) {
      // Dragging left
      double dragFraction = dragDistance / widget.maxDragDistance;
      double newValue = (_startAnimationValue + dragFraction).clamp(0.0, 1.0);
      if (_controller != null) {
        _controller?.value = newValue;
      }
      _dragOffset = 0.0; // Reset drag offset

      if ((_controller?.value ?? 0.0) >= 0.5 && !_hasReachedHalf) {
        _hasReachedHalf = true;
        // Automatically animate to 1.0
        final double remaining = 1.0 - (_controller?.value ?? 0.0);
        final int duration =
            ((_controller?.duration?.inMilliseconds ?? 0) * remaining).round();
        if (duration > 0) {
          _controller?.animateTo(1.0,
              duration: Duration(milliseconds: duration),
              curve: Curves.easeOut);
          _isAnimationBlocked = true;
        } else {
          if (_controller != null) {
            _controller?.value = 1.0;
          }
        }
      }
    } else {
      // Dragging right
      if (_controller != null) {
        _controller?.value =
            _startAnimationValue; // Keep animation controller at current value
      }
      double rightDragOffset = dragDistance.clamp(
          widget.dragRightLimit, 0.0); // Limit to dragRightLimit pixels
      _dragOffset = -rightDragOffset;
      if (rightDragOffset == widget.dragRightLimit) {
        if (_shouldPlayVibration) {
          onCardBlockVibration();
          _shouldPlayVibration = false;
        }
      }
    }
  }

  // Continue the animation when the drag ends
  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_controller?.isAnimating == true ||
        _rightDragController?.isAnimating == true ||
        widget.shouldStartCardCollectionAnimation ||
        _isAnimationBlocked ||
        _cardData.length == 1) {
      // Do not process the gesture if animating or if there's only one card
      return;
    }
    if (_dragOffset != 0.0) {
      // Animate _dragOffset back to zero
      _rightDragAnimation = Tween<double>(
        begin: _dragOffset,
        end: 0.0,
      ).animate(CurvedAnimation(
        parent: _rightDragController ?? AnimationController(vsync: this),
        curve: Curves.easeOutCubic,
      ));
      _rightDragController?.forward(from: 0.0);
    } else if (!_hasReachedHalf) {
      if ((_controller?.value ?? 0.0) >= widget.thresholdValue) {
        // Continue the animation to the end with adjusted duration
        final double remaining = 1.0 - (_controller?.value ?? 0.0);
        final int duration =
            ((_controller?.duration?.inMilliseconds ?? 0) * remaining).round();
        if (duration > 0) {
          _controller?.animateTo(1.0,
              duration: Duration(milliseconds: duration),
              curve: Curves.easeOut);
          _isAnimationBlocked = true;
        } else {
          if (_controller != null) {
            _controller?.value = 1.0;
          }
        }
      } else {
        // Animate back to the start with adjusted duration
        final int duration = ((_controller?.duration?.inMilliseconds ?? 0) *
                (_controller?.value ?? 0.0))
            .round();
        if (duration > 0) {
          _controller?.animateBack(0.0,
              duration: Duration(milliseconds: duration),
              curve: Curves.easeOut);
        } else {
          if (_controller != null) {
            _controller?.value = 0.0;
          }
        }
      }
    }
    _shouldPlayVibration = true;
  }

  List<Widget> _buildStackedCards() {
    // Calculate the total X offset including drag offset
    double xOffsetAnimationValue = _xOffsetAnimation?.value ?? 0.0;
    double rotation = _rotationAnimation?.value ?? 0.0;
    double totalXOffset = -xOffsetAnimationValue * widget.maxDragDistance +
        (_rightDragController?.isAnimating == true
            ? _rightDragAnimation?.value ?? 0.0
            : _dragOffset);

    if ((_controller?.value ?? 0.0) >= 0.5) {
      // Adjust for the second card if only two cards are present
      totalXOffset += _cardData.length == 2
          ? widget.secondCardOffsetStart
          : widget.thirdCardOffsetStart;
    }

    List<Widget> stackChildren = [];

    if (_cardData.length == 1) {
      // Only one card, so only build the top card
      stackChildren.add(_topCardWidget ?? const SizedBox.shrink());
    } else {
      int cardCount = min(_cardData.length, 3);

      if (_isCardSwitched) {
        // After the switch, reverse the order of the stack
        for (int i = 0; i < cardCount; i++) {
          if (i == 0) {
            stackChildren.add(buildTopCard(totalXOffset, rotation));
          } else {
            stackChildren.add(buildCard(cardCount - i));
          }
        }
      } else {
        // Before the switch, normal order
        for (int i = cardCount - 1; i >= 0; i--) {
          if (i == 0) {
            stackChildren.add(buildTopCard(totalXOffset, rotation));
          } else {
            stackChildren.add(buildCard(i));
          }
        }
      }
    }
    return stackChildren;
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: _onHorizontalDragStart,
        onHorizontalDragUpdate: _onHorizontalDragUpdate,
        onHorizontalDragEnd: _onHorizontalDragEnd,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _controller ?? AnimationController(vsync: this),
            _rightDragController ?? AnimationController(vsync: this),
            if (widget.shouldStartCardCollectionAnimation)
              _cardCollectionAnimationController ??
                  AnimationController(vsync: this),
          ]),
          builder: (context, child) {
            return Stack(
              alignment: Alignment.center,
              children: _buildStackedCards(),
            );
          },
        ),
      ),
    );
  }

  // Build the top card with main animation
  Widget buildTopCard(double xOffset, double rotation) {
    if (_topCardWidget == null) {
      return const SizedBox.shrink();
    }

    Widget cardWidget = _isCardSwitched && _cardData.length > 1
        ? (_poppedCardWidget ?? const SizedBox.shrink())
        : (_topCardWidget ?? const SizedBox.shrink());

    return AnimatedBuilder(
      animation: _controller ?? const AlwaysStoppedAnimation(0.0),
      builder: (context, child) {
        // Calculate scale based on animation value before 0.5
        double scale;

        double controllerValue = _controller?.value ?? 0.0;

        if (_cardData.length == 2) {
          if (controllerValue <= 0.5 && _cardData.length > 1) {
            if (controllerValue >= 0.45) {
              double progress = (controllerValue - 0.45) / 0.05;
              scale = 1.0 - 0.05 * progress; // Scale from 1.0 to 0.95
            } else {
              scale = 1.0;
            }
          } else {
            scale = 0.95; // Maintain scale after 0.5
          }
        } else {
          if (controllerValue <= 0.5 && _cardData.length > 1) {
            if (controllerValue >= 0.4) {
              double progress = (controllerValue - 0.4) / 0.1;
              scale = 1.0 - 0.1 * progress; // Scale from 1.0 to 0.9
            } else {
              scale = 1.0;
            }
          } else {
            scale = 0.9; // Maintain scale after 0.5
          }
        }

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..translate(xOffset, 0.0)
            ..translate(
                0.0,
                _isCardSwitched
                    ? (-widget.thirdCardOffsetStart) *
                        ((180 - (_rotationAnimation?.value ?? 0)) / 90)
                    : 0)
            ..setEntry(3, 2, 0.001)
            ..rotateY(rotation * pi / 180)
            ..scale(scale, scale),
          child: child,
        );
      },
      child: cardWidget, // Pass the cardWidget as child to minimize rebuilds
    );
  }

  // Build other cards with their animations
  Widget buildCard(int index) {
    if (_cardData.length <= 1 || index >= _cardData.length) {
      return const SizedBox.shrink();
    }

    Widget? cardWidget;
    if (_isCardSwitched) {
      // After the switch, adjust indices
      if (index == 1) {
        cardWidget = _topCardWidget;
      } else if (index == 2) {
        cardWidget = _secondCardWidget;
      } else {
        return const SizedBox.shrink();
      }
    } else {
      if (index == 1) {
        cardWidget = _secondCardWidget;
      } else if (index == 2) {
        cardWidget = _thirdCardWidget;
      } else {
        return const SizedBox.shrink();
      }
    }

    if (cardWidget == null) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _controller ?? const AlwaysStoppedAnimation(0.0),
      builder: (context, child) {
        double initialOffset = 0.0;
        double initialScale = 1.0;
        double targetScale = 1.0;

        double controllerValue = _controller?.value ?? 0.0;

        // Adjust offsets and scales based on the number of cards
        if (_cardData.length == 2) {
          // Only two cards, use second card parameters
          if (index == 1) {
            // Second card
            initialOffset = widget.secondCardOffsetStart;
            initialScale = widget.secondCardScaleStart;
            targetScale = widget.secondCardScaleEnd;
          }
        } else {
          // Three or more cards
          if (index == 1) {
            // Second card
            initialOffset = widget.secondCardOffsetStart;
            initialScale = widget.secondCardScaleStart;
            targetScale = widget.secondCardScaleEnd;
          } else if (index == 2) {
            // Third card
            initialOffset = widget.thirdCardOffsetStart;
            initialScale = widget.thirdCardScaleStart;
            targetScale = widget.thirdCardScaleEnd;
          }
        }

        // Calculate transformations
        double xOffset = initialOffset;
        double scale = initialScale;

        if (controllerValue <= 0.5) {
          // Before switch
          double progress = controllerValue / 0.5;

          // Move down
          if (_cardData.length == 2) {
            xOffset = initialOffset - widget.secondCardOffsetStart * progress;
          } else {
            xOffset = initialOffset - widget.thirdCardOffsetStart * progress;
          }
          progress = Curves.easeOut.transform(progress);

          // Maintain initial scales before switch
          scale = initialScale; // Keep the scale constant
        } else {
          // After switch
          double progress = (controllerValue - 0.5) / 0.5;

          // Adjust xOffset
          if (_cardData.length == 2) {
            xOffset = initialOffset -
                widget.secondCardOffsetStart +
                widget.secondCardOffsetEnd * progress;
          } else {
            xOffset = initialOffset -
                widget.thirdCardOffsetStart +
                widget.thirdCardOffsetEnd * progress;
          }
          progress = Curves.easeOut.transform(progress);

          // Adjust scales after switch
          scale = initialScale + (targetScale - initialScale) * progress;
        }

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..translate(
                widget.shouldStartCardCollectionAnimation &&
                        _cardCollectionXOffsetAnimation != null
                    ? _cardCollectionXOffsetAnimation
                            ?.drive(CurveTween(
                                curve: Interval((0.4 * (index - 1)), 0.9)))
                            .drive(CurveTween(curve: Curves.easeOut))
                            .drive(Tween(begin: xOffset, end: xOffset + 20))
                            .value ??
                        0
                    : xOffset,
                0.0)
            ..scale(scale, scale),
          child: child,
        );
      },
      child: cardWidget, // Pass the cardWidget as child to minimize rebuilds
    );
  }
}
