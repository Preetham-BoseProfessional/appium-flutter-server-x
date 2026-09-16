import 'dart:io';

import 'package:appium_flutter_server/src/driver.dart';
import 'package:appium_flutter_server/src/exceptions/element_not_found_exception.dart';
import 'package:appium_flutter_server/src/exceptions/flutter_automation_error.dart';
import 'package:appium_flutter_server/src/internal/element_lookup_strategy.dart';
import 'package:appium_flutter_server/src/internal/flutter_element.dart';
import 'package:appium_flutter_server/src/logger.dart';
import 'package:appium_flutter_server/src/models/api/drag_drop.dart';
import 'package:appium_flutter_server/src/models/api/gesture.dart';
import 'package:appium_flutter_server/src/models/api/find_element.dart';
import 'package:appium_flutter_server/src/models/session.dart';
import 'package:appium_flutter_server/src/utils/flutter_settings.dart';
import 'package:appium_flutter_server/src/utils/ui_serialization/element_serializer.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

enum NATIVE_ELEMENT_ATTRIBUTES { enabled, displayed, clickable }

typedef WaitPredicate = Future<bool> Function();

final Map<String, LogicalKeyboardKey> _keyMapping = {
    'escape': LogicalKeyboardKey.escape,
    'esc': LogicalKeyboardKey.escape,
    'enter': LogicalKeyboardKey.enter,
    'return': LogicalKeyboardKey.enter,
    'tab': LogicalKeyboardKey.tab,
    'backspace': LogicalKeyboardKey.backspace,
    'delete': LogicalKeyboardKey.delete,
    'del': LogicalKeyboardKey.delete,
    'space': LogicalKeyboardKey.space,
    'arrowdown': LogicalKeyboardKey.arrowDown,
    'down': LogicalKeyboardKey.arrowDown,
    'arrowup': LogicalKeyboardKey.arrowUp,
    'up': LogicalKeyboardKey.arrowUp,
    'arrowleft': LogicalKeyboardKey.arrowLeft,
    'left': LogicalKeyboardKey.arrowLeft,
    'arrowright': LogicalKeyboardKey.arrowRight,
    'right': LogicalKeyboardKey.arrowRight,
    'home': LogicalKeyboardKey.home,
    'end': LogicalKeyboardKey.end,
    'pageup': LogicalKeyboardKey.pageUp,
    'pagedown': LogicalKeyboardKey.pageDown,
    'select': LogicalKeyboardKey.select,
    'f1': LogicalKeyboardKey.f1,
    'f2': LogicalKeyboardKey.f2,
    'f3': LogicalKeyboardKey.f3,
    'f4': LogicalKeyboardKey.f4,
    'f5': LogicalKeyboardKey.f5,
    'f6': LogicalKeyboardKey.f6,
    'f7': LogicalKeyboardKey.f7,
    'f8': LogicalKeyboardKey.f8,
    'f9': LogicalKeyboardKey.f9,
    'f10': LogicalKeyboardKey.f10,
    'f11': LogicalKeyboardKey.f11,
    'f12': LogicalKeyboardKey.f12,
  };


class ElementHelper {
  static Future<Finder> findElement(Finder by, {String? contextId}) async {
    List<Finder> elementList =
        await findElements(by, contextId: contextId, evaluatePresence: true);
    log("Element found ${elementList.first}");
    return elementList.first;
  }

  static Future<List<Finder>> findElements(Finder by,
      {String? contextId, bool evaluatePresence = false}) async {
    Finder finder = by;

    if (contextId != null) {
      FlutterElement? parent = await FlutterDriver.instance
          .getSessionOrThrow()!
          .elementsCache
          .get(contextId);

      finder = find.descendant(of: parent.by, matching: by);
    }

    final FinderResult<Element> elements = finder.evaluate();
    if (evaluatePresence) {
      await waitForElementExist(FlutterElement.fromBy(finder),
          timeout: Duration(
              milliseconds: FlutterDriver.instance.settings
                  .getSetting(FlutterSettings.flutterElementWaitTimeout)));

      if (elements.isEmpty) {
        throw ElementNotFoundException("Unable to locate element");
      }
    }

    List<Finder> elementList = [];
    for (int i = 0; i < elements.length; i++) {
      elementList.add(finder.at(i));
    }
    return elementList;
  }

  static Future<void> click(FlutterElement element) async {
    WidgetTester tester = _getTester();
    await tester.tap(element.by);
    await pumpAndTrySettle();
  }

  static Future<void> setText(FlutterElement element, String text) async {
    WidgetTester tester = _getTester();

    if (text.startsWith('<') && text.endsWith('>') && text.length > 2) {
      final keyName = text.substring(1, text.length - 1).trim().toLowerCase();
      final logicalKey = _keyMapping[keyName];

      if (logicalKey == null) {
        throw FlutterAutomationException("Unsupported key name: '$keyName'");
      }

      await tester.tap(element.by);
      await pumpAndTrySettle();
      await tester.sendKeyEvent(logicalKey);
      await pumpAndTrySettle();
      return;
    }

    await tester.enterText(element.by, text);
    await tester.pump(const Duration(milliseconds: 400));
  }

  static Future<void> clickAt(GestureModel clickAtModel) async {
    WidgetTester tester = _getTester();

    if (clickAtModel.offset == null) {
      throw ArgumentError("Offset coordinates are mandatory");
    }
    await tester.tapAt(Offset(clickAtModel.offset!.x, clickAtModel.offset!.y));
    await pumpAndTrySettle();
  }

  static Future<void> gestureDoubleClick(GestureModel doubleClickModel) async {
    await TestAsyncUtils.guard(() async {
      final String? elementId = doubleClickModel.origin?.id;
      WidgetTester tester = _getTester();

      FlutterElement? element;
      if (elementId == null && doubleClickModel.locator != null) {
        Finder by = await locateElement(doubleClickModel.locator!);
        element = FlutterElement.fromBy(by);
      } else if (elementId != null) {
        Session session = FlutterDriver.instance.getSessionOrThrow()!;
        element = await session.elementsCache.get(elementId);
      }

      if (element == null) {
        if (doubleClickModel.offset == null) {
          throw ArgumentError(
              "Double click offset coordinates must be provided "
              "if element is not set");
        }

        await tester.tapAt(
            Offset(doubleClickModel.offset!.x, doubleClickModel.offset!.y));
      } else {
        if (doubleClickModel.offset == null) {
          await doubleClick(element);
        } else {
          Rect bounds = getElementBounds(element.by);
          log("Click by offset $bounds");
          await tester.tapAt(Offset(bounds.left + doubleClickModel.offset!.x,
              bounds.top + doubleClickModel.offset!.y));
          await tester.pump(kDoubleTapMinTime);
          await tester.tapAt(Offset(bounds.left + doubleClickModel.offset!.x,
              bounds.top + doubleClickModel.offset!.y));
          await pumpAndTrySettle();
        }
      }
    });
  }

  static Future<void> doubleClick(FlutterElement element) async {
    WidgetTester tester = _getTester();
    await tester.tap(element.by);
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(element.by);
    await pumpAndTrySettle();
  }

  static Future<void> longPress(GestureModel longPressModel) async {
    return TestAsyncUtils.guard(() async {
      final String? elementId = longPressModel.origin?.id;
      WidgetTester tester = _getTester();

      FlutterElement? element;
      if (elementId == null && longPressModel.locator != null) {
        Finder by = await locateElement(longPressModel.locator!);
        element = FlutterElement.fromBy(by);
      } else if (elementId != null) {
        Session session = FlutterDriver.instance.getSessionOrThrow()!;
        element = await session.elementsCache.get(elementId);
      }
      if (element == null) {
        if (longPressModel.offset == null) {
          throw ArgumentError("LongPress offset coordinates must be provided "
              "if element is not set");
        }

        await tester.longPressAt(
            Offset(longPressModel.offset!.x, longPressModel.offset!.y));
      } else {
        if (longPressModel.offset == null) {
          await tester.longPress(element.by);
        } else {
          Rect bounds = getElementBounds(element.by);
          log("Click by offset $bounds");
          await tester.longPressAt(
              Offset(longPressModel.offset!.x, longPressModel.offset!.y));
          await pumpAndTrySettle();
        }
      }
    });
  }

  static Future<String> getText(FlutterElement element) async {
    String extractText(Element el) {
      final buffer = StringBuffer();

      try {
        final widget = el.widget;
        log("The widget is $widget");
        if (widget is Text) {
          buffer.writeln(widget.data ?? widget.textSpan?.toPlainText() ?? "");
        } else if (widget is RichText) {
          buffer.writeln(widget.text.toPlainText());
        } else if (widget is EditableText) {
          buffer.writeln(widget.controller.text);
        } else if (widget is TextField) {
          buffer.write(widget.controller?.value.text);
        }
      } catch (_) {}

      el.visitChildren((child) {
        buffer.write(extractText(child));
      });

      return buffer.toString();
    }

    final evaluated = element.by.evaluate();
    if (evaluated.isEmpty) return "";

    final Element root = evaluated.first;
    return extractText(root).trim();
  }

  static Future<dynamic> getAttribute(
      FlutterElement element, String attribute) async {
    if (NATIVE_ELEMENT_ATTRIBUTES.displayed.name == attribute) {
      return element.by.evaluate().isNotEmpty;
    } else if (NATIVE_ELEMENT_ATTRIBUTES.enabled.name == attribute) {
      return _isElementEnabled(element);
    } else if (NATIVE_ELEMENT_ATTRIBUTES.clickable.name == attribute) {
      return _isElementClickable(element);
    } else {
      final widget = FlutterDriver.instance.tester.widget(element.by);
      log('widget is $widget');

      // Custom handling for SingleChildRenderObjectElement
      if (widget is SingleChildRenderObjectElement) {
        // Get the configuration (the widget property of the element)
        final config = (widget as SingleChildRenderObjectElement).widget;
        if (config is SingleChildRenderObjectWidget) {
          log('Inside if block for SingleChildRenderObjectWidget');
          final Widget? child = config.child;
          if (child != null) {
            log('Inside if block for child of SingleChildRenderObjectWidget. The child is $child');
            List<DiagnosticsNode> childNodes =
                child.toDiagnosticsNode().getProperties();
            List<DiagnosticsNode> data = List<DiagnosticsNode>.from(childNodes);
            log('The child nodes are $childNodes');
            log('The data is $data');
            if (attribute == "all") {
              Map<String, dynamic> values = {};
              for (DiagnosticsNode node in data) {
                values[node.name ?? "unknown"] = node.value?.toString();
              }
              return values;
            } else {
              try {
                return data
                    .firstWhere((node) => node.name == attribute)
                    .value
                    ?.toString();
              } catch (err) {
                log(err);
                return null;
              }
            }
          }
        }
        // No child or not a SingleChildRenderObjectWidget, fallback to default logic below
      }

      // Custom handling for Semantics widget
      if (widget is Semantics) {
        log('Inside if block for Semantics widget');
        log('Semantics enabled ${SemanticsBinding.instance.semanticsEnabled}');
        final properties = widget.properties;
        log('properties of Semantics widget are ${properties.toString()}');
        final diagnostics = properties.toDiagnosticsNode().getProperties();
        List<DiagnosticsNode> data = List<DiagnosticsNode>.from(diagnostics);
        if (attribute == "all") {
          Map<String, dynamic> values = {};
          for (DiagnosticsNode node in data) {
            values[node.name ?? "unknown"] = node.value?.toString();
          }
          return values;
        } else {
          try {
            return data
                .firstWhere((node) => node.name == attribute)
                .value
                ?.toString();
          } catch (err) {
            log(err);
            return null;
          }
        }
      }

      List<DiagnosticsNode> nodes = FlutterDriver.instance.tester
          .widget(element.by)
          .toDiagnosticsNode()
          .getProperties();
      List<DiagnosticsNode> data = [];
      try {
        data = List<DiagnosticsNode>.from(
          FlutterDriver.instance.tester
              .getSemantics(element.by)
              .toDiagnosticsNode()
              .getChildren()
              .first
              .getProperties(),
        );
        FlutterDriver.instance.tester
            .getSemantics(element.by)
            .getSemanticsData()
            .toDiagnosticsNode()
            .getProperties()
            .forEach((element) {
          log("Semantics data : ${element.name} -> ${element.value}");
        });
      } catch (err) {
        log(err);
      }
      data.addAll(nodes);
      log("Available attributes for the element : ${element.by}");
      for (DiagnosticsNode node in nodes) {
        log("${node.name} -> ${node.value}");
      }
      log("Attribute in else block");
      log(data);
      try {
        if (attribute == "all") {
          log('Inside all');
          log('The data is $data');
          Map<String, dynamic> values = {};
          for (DiagnosticsNode node in data) {
            log('node name ${node.name.toString()}');
            log('node value ${node.value.toString()}');
            log("${node.name.toString()} -> ${node.value.toString()}");
            var value = node.name.toString();
            values[value] = node.value.toString();
          }
          return values;
        } else {
          return data
              .firstWhere((node) => node.name == attribute)
              .value
              .toString();
        }
      } catch (err) {
        log(err);
        return null;
      }
    }
  }

  static WidgetTester _getTester() {
    return FlutterDriver.instance.tester;
  }

  static Future<Finder> locateElement(FindElementModel model,
      {bool evaluatePresence = true}) async {
    /// Support for backward compatibility
    final String method = model.strategy.startsWith("-flutter")
        ? model.strategy
        : '-flutter ${model.strategy.trim()}';
    final String? contextId = model.context == "" ? null : model.context;

    if (contextId == null) {
      log('"method: $method, selector: ${model.selector}');
    } else {
      log('"method: $method, selector: ${model.selector}, contextId: $contextId');
    }

    // Since the appium python client does not have a specific semantics identifier locator option,
    // the -flutter key option has been repurposed.
    // Special handling of flutter key has been added here.
    // This tries to find the semantics widget id with the string same as that of the supplied selector.
    // We want to prioritize finding by semantics identifier. Not all widgets might be set with key.
    // If the element is not found with the semantics identifier, then we fallback to finding an element
    // the same key.
    if (method == ElementLookupStrategy.BY_KEY.name) {
      try {
        log('Trying to find the element with key ${model.selector} using semantics identifier');
        final semanticsStrategy = ElementLookupStrategy.values
            .firstWhere((val) => val.name == '-flutter semantics_identifier');
        final Finder semanticsFinder = await semanticsStrategy.toFinder(model);

        if (evaluatePresence) {
          return await findElement(semanticsFinder, contextId: contextId);
        } else {
          return semanticsFinder;
        }
      } catch (e, st) {
        log('Failed to find using semantics_identifier. Falling back to key. Error: $e \n Stacktrace: $st');
      }
    }

    // Get the strategy and create the finder
    final strategy =
        ElementLookupStrategy.values.firstWhere((val) => val.name == method);
    final Finder by = await strategy.toFinder(model);

    if (evaluatePresence) {
      return await findElement(by, contextId: contextId);
    } else {
      return by;
    }
  }

  static Rect getElementBounds(Finder by) {
    var tester = _getTester();
    return Rect.fromPoints(tester.getTopLeft(by), tester.getBottomRight(by));
  }

  static Size getElementSize(Finder by) {
    var tester = _getTester();
    return tester.getSize(by);
  }

  static String getElementName(Finder by) {
    var tester = _getTester();
    Element element = tester.element(by);
    if (element is RenderObjectElement &&
        element.renderObject.debugSemantics?.label != null) {
      final String? semanticsLabel = element.renderObject.debugSemantics?.label;
      if (semanticsLabel != null) {
        return semanticsLabel.toString();
      }
    }
    return element.widget.runtimeType.toString();
  }

  static DiagnosticsNode? _getElementPropertyNode(Finder by, String propertry) {
    try {
      return FlutterDriver.instance.tester
          .widget(by)
          .toDiagnosticsNode()
          .getProperties()
          .where((node) => node.name == propertry)
          .first;
    } catch (e) {
      return null;
    }
  }

  static dynamic _isElementEnabled(FlutterElement element) {
    String attribute = NATIVE_ELEMENT_ATTRIBUTES.enabled.name;

    // Improving checking of enabled property of the element.
    // Direct widget type ispection is preferred over diagnostics.
    // Some widgets may not even expose the enabled state at all through diagnostics.
    final widget = FlutterDriver.instance.tester.widget(element.by);
    if (widget is ButtonStyleButton) {
      return widget.onPressed != null;
    } else if (widget is Switch) {
      return widget.onChanged != null;
    } else if (widget is Slider) {
      return widget.onChanged != null;
    } else if (widget is TextField) {
      return widget.enabled == null ? true : widget.enabled!;
    } else if (widget is Semantics) {
      return widget.properties.enabled == null
          ? true
          : widget.properties.enabled!;
    }

    // Fallback to diagnostics
    DiagnosticsNode? enabledProperty =
        _getElementPropertyNode(element.by, attribute);
    if (enabledProperty != null && enabledProperty.value is bool) {
      return enabledProperty.value as bool;
    }

    return true;
  }

  static bool _isElementClickable(FlutterElement flutterElement) {
    /*
     * Reference taken from https://github.com/flutter/flutter/blob/master/packages/flutter_test/lib/src/controller.dart#L1880
     * Method: _getElementPoint
     */
    TestAsyncUtils.guardSync();
    Finder finder = flutterElement.by;
    WidgetTester tester = _getTester();
    IntegrationTestWidgetsFlutterBinding binding =
        FlutterDriver.instance.binding;

    final Iterable<Element> elements = finder.evaluate();
    final Element element = elements.single;
    final RenderObject? renderObject = element.renderObject;
    if (renderObject == null) {
      log('The finder "$finder"  found an element, but it does not have a corresponding render object. '
          'Maybe the element has not yet been rendered?');
      return false;
    }
    if (renderObject is! RenderBox) {
      log('The finder "$finder"  found an element whose corresponding render object is not a RenderBox (it is a ${renderObject.runtimeType}: "$renderObject"). '
          'Unfortunately it only supports targeting widgets that correspond to RenderBox objects in the rendering.');
      return false;
    }
    final RenderBox box = element.renderObject! as RenderBox;
    final Offset location = box.localToGlobal(box.size.center(Offset.zero));
    final FlutterView view = tester.viewOf(finder);
    final HitTestResult result = HitTestResult();
    binding.hitTestInView(result, location, view.viewId);
    final bool found =
        result.path.any((HitTestEntry entry) => entry.target == box);
    if (!found) {
      return false;
    }
    return true;
  }

  static Future<void> waitForElementExist(FlutterElement element,
      {required Duration timeout}) async {
    await waitFor(() async {
      try {
        return element.by.evaluate().isNotEmpty;
      } catch (e) {
        return false;
      }
    },
        timeout: timeout,
        errorMessage:
            "Element with locator ${element.by.describeMatch(Plurality.one)} is not present in DOM");
  }

  static Future<void> waitForElementVisible(FlutterElement element,
      {required Duration timeout}) async {
    await waitFor(() async {
      try {
        return element.by.hitTestable().evaluate().isNotEmpty;
      } catch (e) {
        return false;
      }
    },
        timeout: timeout,
        errorMessage:
            "Element with locator ${element.by.describeMatch(Plurality.one)} is not visible");
  }

  static Future<void> waitForElementAbsent(FlutterElement element,
      {required Duration timeout}) async {
    await waitFor(
      () async {
        try {
          return element.by.evaluate().isEmpty;
        } catch (e) {
          return true;
        }
      },
      timeout: timeout,
      errorMessage:
          "Element with locator ${element.by.describeMatch(Plurality.one)} not visible",
    );
  }

  static Future<void> waitForElementEnable(FlutterElement element) async {
    await waitFor(() async {
      return bool.parse(await ElementHelper.getAttribute(
          element, NATIVE_ELEMENT_ATTRIBUTES.enabled.name));
    },
        errorMessage:
            "Element with locator ${element.by.describeMatch(Plurality.one)} not enabled");
  }

  static Future<void> waitForElementClickable(FlutterElement element) async {
    await waitFor(() async {
      return bool.parse(await ElementHelper.getAttribute(
          element, NATIVE_ELEMENT_ATTRIBUTES.clickable.name));
    },
        errorMessage:
            "Element with locator ${element.by.describeMatch(Plurality.one)} not clickable");
  }

  static Future<void> waitFor(
    WaitPredicate predicate, {
    String? errorMessage,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    WidgetTester tester = FlutterDriver.instance.tester;
    final end = tester.binding.clock.now().add(timeout);

    do {
      if (tester.binding.clock.now().isAfter(end)) {
        throw Exception(errorMessage != null
            ? '$errorMessage with ${timeout.inSeconds} seconds'
            : 'Timed out waiting for condition');
      }
      if (Platform.isAndroid) {
        await pumpAndTrySettle(timeout: const Duration(milliseconds: 200));
      }
      await Future.delayed(const Duration(milliseconds: 100));
    } while (!(await predicate()));
  }

  static Future<void> dragAndDrop(DragAndDropModel model) async {
    return TestAsyncUtils.guard(() async {
      WidgetTester tester = _getTester();
      final String sourceElementId = model.source.id;
      final String targetElementId = model.target.id;
      Session session = FlutterDriver.instance.getSessionOrThrow()!;
      FlutterElement sourceEl =
          await session.elementsCache.get(sourceElementId);
      FlutterElement targetEl =
          await session.elementsCache.get(targetElementId);
      final Offset sourceElementLocation = tester.getCenter(sourceEl.by);
      final Offset targetElementLocation = tester.getCenter(targetEl.by);
      final TestGesture gesture =
          await tester.startGesture(sourceElementLocation, pointer: 7);
      await gesture.moveTo(targetElementLocation);
      await tester.pump();
      await gesture.up();
      await tester.pump();
    });
  }

  static Future<Finder> scrollUntilVisible({
    required FindElementModel finder,
    FindElementModel? scrollView,
    double? delta,
    AxisDirection? scrollDirection,
    int? maxScrolls,
    Duration? settleBetweenScrollsTimeout,
    Duration? dragDuration,
  }) async {
    delta ??= FlutterDriver.instance.settings
        .getSetting(FlutterSettings.flutterScrollDelta);
    maxScrolls ??= FlutterDriver.instance.settings
        .getSetting(FlutterSettings.flutterScrollMaxIteration);
    WidgetTester tester = _getTester();
    Finder scrollViewElement = scrollView != null
        ? await locateElement(scrollView)
        : find.byType(Scrollable);
    Finder elementToFind = await locateElement(finder, evaluatePresence: false);

    await waitForElementExist(FlutterElement.fromBy(scrollViewElement),
        timeout: Duration(
            milliseconds: FlutterDriver.instance.settings
                .getSetting('flutterElementWaitTimeout')));
    AxisDirection direction;
    if (scrollDirection == null) {
      if (scrollViewElement.evaluate().first.widget is Scrollable) {
        direction =
            tester.firstWidget<Scrollable>(scrollViewElement).axisDirection;
      } else {
        direction = AxisDirection.down;
      }
    } else {
      direction = scrollDirection;
    }

    return TestAsyncUtils.guard<Finder>(() async {
      Offset moveStep;
      switch (direction) {
        case AxisDirection.up:
          moveStep = Offset(0, delta!);
        case AxisDirection.down:
          moveStep = Offset(0, -delta!);
        case AxisDirection.left:
          moveStep = Offset(delta!, 0);
        case AxisDirection.right:
          moveStep = Offset(-delta!, 0);
      }

      scrollViewElement = scrollViewElement.first;
      dragDuration ??= const Duration(milliseconds: 100);
      settleBetweenScrollsTimeout ??= const Duration(seconds: 5);

      var iterationsLeft = maxScrolls!;
      while (iterationsLeft > 0 &&
          elementToFind.hitTestable().evaluate().isEmpty) {
        await tester.timedDrag(
          scrollViewElement,
          moveStep,
          dragDuration!,
        );
        await pumpAndTrySettle(timeout: settleBetweenScrollsTimeout!);
        iterationsLeft -= 1;
      }

      if (iterationsLeft <= 0) {
        throw FlutterAutomationException("Wait timeout");
      }

      return elementToFind;
    });
  }

  static Future<void> pumpAndTrySettle({
    Duration duration = const Duration(milliseconds: 100),
    EnginePhase phase = EnginePhase.sendSemanticsUpdate,
    Duration timeout = const Duration(milliseconds: 200),
  }) async {
    try {
      WidgetTester tester = _getTester();
      await tester.pumpAndSettle(
        duration,
        phase,
        timeout,
      );
    } on FlutterError catch (err) {
      if (err.message == 'pumpAndSettle timed out') {
        //This method ignores pumpAndSettle timeouts on purpose
      } else {
        rethrow;
      }
    }
  }

  static Future<Map<String, dynamic>> _serializeElement(
    Element element, {
    Set<Element>? visited,
    int depth = 0,
  }) =>
      ElementSerializer.serialize(element, visited: visited, depth: depth);

  static Future<List<Map<String, dynamic>>> getRenderTreeByType({
    String? widgetType,
    String? text,
    String? key,
  }) async {
    final tester = _getTester();
    final rootElement = tester.binding.rootElement;

    if ((widgetType == null || widgetType.isEmpty) && rootElement != null) {
      return [await _serializeElement(rootElement)];
    }
    if (rootElement == null) {
      return [];
    }

    final matchedElements = <Element>[];

    Future<void> search(Element element) async {
      final widget = element.widget;
      final typeMatches = widget.runtimeType.toString() == widgetType;
      final keyMatches =
          key == null || widget.key?.toString().contains(key) == true;
      bool textMatches = text == null;
      if (text != null &&
          (widget is Text ||
              widget is RichText ||
              widget is EditableText ||
              widget is TextField)) {
        try {
          final flutterElement = FlutterElement.fromBy(find.byWidget(widget));
          final elementText = await ElementHelper.getText(flutterElement);
          textMatches = elementText == text;
        } catch (_) {
          textMatches = false;
        }
      }

      if (typeMatches && keyMatches && textMatches) {
        matchedElements.add(element);
      }

      element.visitChildren(search);
    }

    await search(rootElement);
    if (matchedElements.isEmpty) {
      return [];
    }
    final results = <Map<String, dynamic>>[];

    for (final element in matchedElements) {
      results.add(await _serializeElement(element));
    }
    return results;
  }
}
