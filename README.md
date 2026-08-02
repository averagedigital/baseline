# Baseline

iOS-приложение для сбора тренировочной телеметрии, хранения данных и персонализации ответов ЛЛМ

## Стек

- Swift 6;
- SwiftUI;
- iOS 17+;
- Swift Package Manager;
- GRDB 7.11.1;
- SQLite и FTS5;
- Swift Testing;
- Xcode 26;
- XcodeGen.

## Модули

- `AthleteCore` — evidence, provenance, memory, module и plan contracts;
- `AthleteStore` — GRDB migrations, evidence ledger, memory dependencies и FTS5;
- `AthleteAgents` — context compiler, grounding verifier, State Builder, Coach и plan approval;
- `Baseline` — iOS-приложение и визуальный слой.

## Структура

```text
apps/ios/Baseline/     iOS target и Xcode project
packages/swift/        Swift packages и тесты
```

## Тесты

```bash
cd packages/swift
swift test
```

```bash
cd apps/ios/Baseline
xcodebuild \
  -project Baseline.xcodeproj \
  -scheme Baseline \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  test CODE_SIGNING_ALLOWED=NO
```
