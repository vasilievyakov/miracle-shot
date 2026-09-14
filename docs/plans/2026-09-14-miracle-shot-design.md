# Miracle Shot — дизайн

Дата: 2026-09-14
Статус: принят, фазы 1–3 идут в реализацию; фаза 4 отложена.

## 1. Что это

Menu-bar приложение для macOS, кастомная замена CleanShot X для личного использования. Живет по хоткеям, без иконки в доке. Нативный Swift (AppKit + SwiftUI), сборка через SwiftPM, тесты через XCTest.

Сознательно вырезано: запись видео/GIF, облако и шеринг по ссылке.

Ключевые мотивы кастомной версии:
- свой визуальный стиль: пресеты фонов, шрифты, цвета аннотаций в JSON, легко добавлять агентские;
- свой воркфлоу: куда сохранять, как именовать, post-capture hook;
- AI-пресеты над скриншотом (фаза 4);
- полный контроль над кодом, без подписки.

## 2. Фазы

### Фаза 1 — ядро захвата
- Хоткеи: область, окно, весь экран. Настраиваются.
- Оверлей выделения: перекрестие, лупа, размеры выделения, снап к окнам под курсором, Esc отменяет, клик без движения снимает окно.
- После захвата: картинка в буфере обмена и в файле (папка и шаблон имени из настроек), запись в историю.
- Плавающее превью в углу экрана на N секунд: кнопки «редактор», «пин», «OCR», «AI» (заглушка до фазы 4), Drag&Drop миниатюры в другое окно. Без действий исчезает.
- История захватов в меню-баре (последние N, открыть в Finder, открыть в редакторе).
- Окно настроек: хоткеи, папка, шаблон имени, таймаут превью.

### Фаза 2 — редактор аннотаций
- Инструменты: стрелка, прямоугольник, эллипс, линия, карандаш, текст, нумерованные шаги, размытие/пикселизация, маркер-подсветка, кроп.
- Стиль инструмента: цвет, толщина, шрифт, размер.
- Undo/Redo.
- Фоны-пресеты: цвет, градиент, картинка; паддинг, скругление углов, тень. Пресеты в JSON в Application Support, встроенные — в ресурсах.
- Экспорт: буфер, файл, Drag&Drop из окна редактора.

### Фаза 3 — утилиты
- Пин: картинка в плавающей панели поверх всех окон; перемещение за фон, прозрачность и масштаб с клавиатуры/колесом, закрыть по Esc или двойным кликом.
- OCR: Vision, языки ru + en, результат текстом в буфер, уведомление с первыми строками.
- Скроллинг-захват: выбрать окно, приложение скроллит его и склеивает кадры в одно длинное изображение, результат идет по обычному потоку (буфер, файл, превью).

### Фаза 4 — AI и автоматизация (отложено)
- Пресеты: имя, промпт, формат ответа (text / markdown / csv / json), куда результат (буфер / окно / файл), хоткей.
- Встроенные: «извлечь таблицу», «перевести на русский», «перевести на английский», «alt-text».
- Claude API, ключ в Keychain.
- Post-capture hook: shell-скрипт с путем к файлу в аргументе.

## 3. Архитектура

Один SwiftPM-пакет `MiracleShot`, два таргета и тестовый таргет.

```
MiracleShot/
  Package.swift
  Sources/
    MiracleShotCore/        библиотека, Foundation + CoreGraphics + CoreImage, без AppKit
    MiracleShotApp/         executable, AppKit + SwiftUI
  Tests/
    MiracleShotCoreTests/   XCTest
  Resources/
    presets/                встроенные пресеты фонов (JSON)
  scripts/
    build-app.sh            сборка "Miracle Shot.app"
  docs/plans/
```

Правило зависимостей: `MiracleShotApp` -> `MiracleShotCore`, никогда наоборот. В Core нет ни одного `import AppKit`.

Минимальная macOS: 14 (нужен `SCScreenshotManager`). Swift 6, strict concurrency: сервисы App-слоя — `@MainActor` классы или акторы.

### 3.1 MiracleShotCore

- `Capture` — `CGImage`, `timestamp`, `sourceAppBundleID?`, `sourceWindowTitle?`, `bounds`, `scaleFactor`.
- `CaptureState` — enum состояний захвата: `idle`, `selecting(mode)`, `capturing`, `previewing(capture)`. Переходы описаны как чистая функция `reduce(state, event) -> state`. Инварианты: нельзя начать второй захват во время первого; Esc из `selecting` ведет в `idle`.
- `NamingTemplate` — парсит `{date}`, `{time}`, `{app}`, `{seq}`, отдает имя файла. Безопасная замена символов.
- `Annotation` — enum с associated values: `arrow`, `rect`, `ellipse`, `line`, `freehand`, `text`, `step`, `blur`, `highlight`. У каждой `id: UUID`, `style: AnnotationStyle`.
- `AnnotationStyle` — `strokeColor`, `fillColor?`, `lineWidth`, `fontName`, `fontSize`.
- `BackgroundPreset` — `Codable`: `id`, `name`, `fill` (`solid` / `linearGradient` / `image`), `padding`, `cornerRadius`, `shadow`.
- `Document` — `source: CGImage`, `annotations: [Annotation]`, `background: BackgroundPreset?`, `cropRect: CGRect?`.
- `AnnotationRenderer` — `render(_ document: Document) -> CGImage`. Детерминированный. Blur/pixelate через CoreImage.
- `UndoStack<T>` — массив снимков, `push`, `undo`, `redo`, ограничение глубины.
- `ImageStitcher` — `stitch(frames: [CGImage]) -> CGImage`. Ищет перекрытие соседних кадров сравнением строк пикселей; устойчив к статичным шапкам окна (исключает верхнюю область по эвристике).
- `HistoryIndex` — `Codable` список записей (путь, дата, размер, источник), ограничение N, чтение/запись в JSON.
- `Settings` — `Codable`: хоткеи, папка, шаблон имени, таймаут превью, список пресетов. JSON в `~/Library/Application Support/Miracle Shot/`.
- `OCRResult` / `TextBlock` — текст + rect, чтобы OCR-сервис отдавал типизированный результат.

### 3.2 MiracleShotApp

- `AppDelegate` / `MenuBarController` — `NSStatusItem`, меню: захваты, история, настройки, выход. `LSUIElement = true`.
- `HotkeyManager` — Carbon `RegisterEventHotKey`, без Accessibility. Маппинг хоткей -> действие.
- `CaptureCoordinator` — единственный владелец `CaptureState`; принимает события от хоткеев, оверлея, превью; вызывает сервисы.
- `CaptureService` — ScreenCaptureKit: `SCShareableContent` для списка окон/экранов, `SCScreenshotManager.captureImage` для снимка области/окна/экрана. Требует разрешение Screen Recording.
- `SelectionOverlay` — borderless `NSPanel` уровня `.screenSaver` на каждый экран; рисует затемнение, рамку, размеры, лупу; определяет окно под курсором по `SCShareableContent`.
- `QuickPreviewPanel` — плавающая `NSPanel` в правом нижнем углу; миниатюра, кнопки действий, таймер автоскрытия, `NSDraggingSource` для Drag&Drop файла.
- `EditorWindow` — `NSWindow` с SwiftUI `Canvas`; тулбар инструментов и стилей; хранит `Document`, рендер превью и экспорт через `AnnotationRenderer`.
- `PinPanel` — плавающая `NSPanel` с картинкой, `isMovableByWindowBackground`, прозрачность и масштаб.
- `OCRService` — обертка над Vision `VNRecognizeTextRequest`, `recognitionLanguages = ["ru", "en"]`.
- `ScrollCaptureService` — выбирает окно, шлет `CGEvent` scroll, снимает кадры через `CaptureService`, отдает `ImageStitcher`.
- `ClipboardService`, `FileSaveService` — тонкие обертки.
- `SettingsWindow` — SwiftUI-форма над `Settings`.
- `HistoryMenu` — подменю из `HistoryIndex`.

### 3.3 Сборка и распространение

`scripts/build-app.sh`:
1. `swift build -c release`;
2. собирает `build/Miracle Shot.app/Contents/{MacOS,Resources}`;
3. пишет `Info.plist`: `CFBundleIdentifier = agency.blackbloom.miracleshot`, `LSUIElement = true`, `NSScreenCaptureUsageDescription`, `CFBundleIconFile`;
4. `codesign --force --sign - --identifier agency.blackbloom.miracleshot` — стабильный ad-hoc identifier, чтобы разрешение Screen Recording не слетало при каждой пересборке;
5. опционально копирует в `/Applications`.

## 4. Потоки данных

### 4.1 Захват области

```
хоткей -> HotkeyManager -> CaptureCoordinator.begin(.area)
  -> SelectionOverlay.show() -> пользователь тянет рамку -> rect + display
  -> CaptureService.capture(rect, display) -> CGImage
  -> Capture(...)
  -> параллельно: ClipboardService.copy, FileSaveService.save(NamingTemplate), HistoryIndex.append
  -> QuickPreviewPanel.show(capture)
```

Захват окна: тот же поток, но оверлей подсвечивает окно под курсором и по клику отдает его `SCWindow`. Весь экран: оверлей пропускается.

### 4.2 Из превью
- Редактор: `EditorWindow.open(Document(source: capture.image))`.
- Пин: `PinPanel.show(capture.image)`.
- OCR: `OCRService.recognize(capture.image)` -> буфер + уведомление.
- Drag: файл из истории как `NSDraggingItem`.

### 4.3 Редактор
`Document` -> пользователь добавляет `Annotation` -> `UndoStack.push` -> `AnnotationRenderer.render` для превью -> экспорт тем же рендером.

### 4.4 Скроллинг-захват
Окно -> кадр 0 -> scroll на высоту окна минус перекрытие -> кадр 1 -> ... пока кадры не перестанут меняться или не достигнут лимита -> `ImageStitcher.stitch` -> обычный поток захвата.

## 5. Обработка ошибок

- Нет разрешения Screen Recording: показать алерт с кнопкой «Открыть настройки», не падать. Проверка при старте и перед каждым захватом.
- Захват вернул nil: уведомление, состояние обратно в `idle`.
- Папка сохранения недоступна: fallback в `~/Pictures/Miracle Shot/`, уведомление.
- OCR не нашел текст: уведомление «Текст не найден», буфер не трогаем.
- Скроллинг-захват: лимит 50 кадров и 30 секунд; если перекрытие не найдено — вернуть просто конкатенацию и предупредить.
- Ошибка чтения `Settings` или `HistoryIndex` JSON: логировать, продолжить с дефолтами, битый файл переименовать в `.broken`.

## 6. Тестирование

- Core: XCTest через `swift test`. TDD: тест первым, затем минимальная реализация.
  - `CaptureStateTests` — все переходы и инварианты.
  - `NamingTemplateTests` — подстановки, экранирование, последовательность.
  - `AnnotationRendererTests` — рендер документа известного размера, проверка пикселей в контрольных точках; паддинг и скругление фона; blur реально меняет область.
  - `UndoStackTests`.
  - `ImageStitcherTests` — длинное синтетическое изображение режется на перекрывающиеся кадры, склеивается, сравнивается с оригиналом; случай статичной шапки.
  - `HistoryIndexTests`, `SettingsTests` — round-trip JSON, миграция с битого файла.
  - `BackgroundPresetTests` — декодирование встроенных пресетов.
- App: ручной чек-лист на каждую задачу плана; `scripts/build-app.sh` как smoke-тест; отдельный пункт — разрешение Screen Recording переживает пересборку.

## 7. Решения и почему

- Нативный Swift, а не Tauri/Electron: оверлей, пин поверх окон, глобальные хоткеи, ScreenCaptureKit и Vision — все системное, обертки для веб-стека дороже самой фичи.
- SwiftPM без .xcodeproj: собираемость из терминала субагентами, никаких GUI-шагов. Xcode нужен только ради XCTest и SDK.
- Carbon hotkeys вместо CGEventTap: не требует Accessibility-разрешения.
- Один рендерер для экрана и экспорта: WYSIWYG и тестируемость.
- Undo как снимки массива аннотаций: аннотаций мало, снимки дешевы, код тривиален.
- Пресеты фонов в JSON: «свой визуальный стиль» без пересборки.

## 8. Открытые вопросы

- Иконка приложения и цветовая схема — сделать в фазе 2 вместе с пресетами.
- Нужен ли режим «захват с задержкой» (таймер) — не в фазах 1–3.
- Точная эвристика статичной шапки в `ImageStitcher` — уточнить на реальных окнах в фазе 3.
