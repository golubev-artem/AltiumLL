# Обновление Description / Detailed Description в SamacSys.SchLib — статус

Последнее обновление: 2026-07-16

## Задача

В библиотеке `SamacSys.SchLib` (папка `BACKUP_TEST`) у многих компонентов
некорректно/неинформативно заполнено поле **Description**, а поля
**Detailed Description** нет вообще ни у одного из компонентов. Нужно
восстановить оба поля по данным с digikey.com и записать обратно в
библиотеку, не трогая при этом графику/пины компонентов.

Библиотека целиком: **1235 компонентов**.

## Почему не редактируем файл напрямую

`.SchLib` — это OLE Compound File (тот же контейнер, что .doc/.xls). Внутри
каждый компонент хранится как поток с текстовыми pipe-record'ами вперемешку
с бинарными записями пинов (геометрия). Ручной побайтовый парсинг/запись
слишком рискован — можно повредить пины. Поэтому правки делаются изнутри
**Altium Designer через DelphiScript** (штатный Library API), который сам
безопасно сериализует файл при сохранении.

## Инфраструктура (файлы в BACKUP_TEST)

- **`UpdateDescriptions.pas`** — DelphiScript. Открыть `SamacSys.SchLib` в
  Altium, сделать его активным документом, запустить процедуру
  `ApplyDigikeyDescriptions` (Scripting System → Run). Скрипт:
  - читает tsv-файл, путь задан константой `DataFilePath` в начале файла
    (**перед каждым новым батчем меняйте эту константу** на нужный `.tsv`);
  - формат tsv: `DesignItemID<TAB>Description<TAB>DetailedDescription`,
    третье поле может быть пустым — тогда Detailed Description для этого
    компонента просто не трогается;
  - обновляет `Component.ComponentDescription`;
  - добавляет параметр "Detailed Description", если его нет, либо обновляет
    существующий;
  - **не трогает** компоненты, которых нет в tsv;
  - пишет лог `update_log_<YYYY-MM-DD_HH-NN-SS>.txt` с построчным
    отчётом (старое/новое Description, что произошло с Detailed
    Description) и сводкой в конце;
  - после запуска — **сохранить библиотеку вручную (Ctrl+S)**.

## Формат данных от DigiKey

Есть два источника:

1. **Точечный веб-поиск по одному partnumber** (использовался в пилоте) —
   даёт и Description, и Detailed Description, но медленно и есть риск,
   что поиск подставит похожий partnumber другого производителя вместо
   "не найдено" (уже несколько раз ловили такое на схожих обозначениях
   Degson/Reliance North America) — такие случаи нужно откладывать в
   отдельный список, а не применять вслепую.

2. **DigiKey "Upload a List"** (bulk-загрузка списка partnumber'ов,
   экспорт в CSV) — быстро и надёжно даёт **только короткое Description**
   (колонки Manufacturer Part Number, Manufacturer Name, Description,
   Requested Part Number и др.) — **колонки Detailed Description там нет**,
   в интерфейсе такую колонку добавить нельзя (проверено). Матчить нужно
   по колонке **"Requested Part Number"**, а не "Manufacturer Part Number"
   (DigiKey иногда нормализует сам partnumber). Важно: иногда DigiKey вместо
   честного "не найдено" подставляет в "Requested Part Number" какой-то свой
   внутренний номер — такие строки не являются надёжным совпадением с тем,
   что реально искали, и должны фильтроваться отдельно (см. ниже).

## Сделано

### Пилотная пачка (веб-поиск по одному, вручную verified)
- `digikey_updates.tsv` — **11 компонентов**, Description + Detailed
  Description, дословно сверенные с страницей DigiKey. Применено скриптом,
  результат проверен пользователем — **корректно**.
- `digikey_needs_verification.tsv` — 3 компонента, где Detailed Description
  не удалось дословно подтвердить (142-0701-801, 1861044, 1861057) —
  не применялись.
- `digikey_missed.txt` — 7 компонентов, которых нет на DigiKey либо был
  пойман ложный матч на другого производителя (Reliance North America
  вместо Degson) — не применялись.

### Батч part00 (bulk-выгрузка DigiKey, только Description)
- Список запроса: `digikey_upload_list_part00.txt` (250 partnumber'ов,
  часть пользователь удалил перед загрузкой — какие именно, не
  зафиксировано).
- Экспорт DigiKey: `digikey_upload_list_part00_FULL.txt` (сырой CSV).
- `digikey_updates_part00.tsv` — **159 компонентов**, только Description
  (Detailed Description пусто). **Применено скриптом, проверено по логу
  `update_log_2026-07-16_14-27-19.txt`: 159 обновлено, 0 не найдено.
  Закоммичено и запушено (коммит `d7f3f68` / `upd`).**
- `digikey_missed_part00.txt` — 91 partnumber без надёжного совпадения
  (либо не найден DigiKey, либо удалён пользователем заранее — не
  различить).
- `digikey_needs_verification_part00.txt` — 31 подозрительная строка,
  где DigiKey подставил чужой номер вместо "не найдено" — не применялись,
  нужна ручная проверка.

### Ещё не обработано
- `digikey_upload_list_part01.txt` … `digikey_upload_list_part04.txt` —
  остальные ~980 partnumber'ов библиотеки, разбитые на пачки по 250/230,
  **ещё не загружались на DigiKey**.
- **Detailed Description отсутствует у ВСЕХ 1235 компонентов** — bulk-путь
  его не даёт в принципе, для полного покрытия нужен либо точечный
  веб-поиск (медленно), либо DigiKey Product Information API (нужна
  регистрация разработчика на developer.digikey.com, OAuth client
  id/secret — с ним можно получить оба поля разом и по одному
  запросу на partnumber, но без ручной беготни по сайту).
- 91 (part00) + 7 (пилот) = 98 подтверждённо отсутствующих на DigiKey
  компонентов пока не имеют финального решения (оставить как есть? какое
  Description ставить?).
- 31 (part00) + 3 (пилот) = 34 требуют ручной проверки перед применением.

## Как продолжить (в т.ч. с другого ПК)

1. `git pull` — подтянуть все файлы из `BACKUP_TEST` (список выше).
2. Для следующей пачки (`part01.txt` и далее): зайти на digikey.com →
   Upload a List → загрузить файл → экспортировать результат в CSV/txt
   рядом (например `digikey_upload_list_part01_FULL.txt`) → передать мне
   (Claude) на обработку — я соберу `digikey_updates_part01.tsv` +
   `digikey_missed_part01.txt` + `digikey_needs_verification_part01.txt`
   по той же логике, что и для part00.
3. Перед запуском скрипта в Altium — поменять `DataFilePath` в
   `UpdateDescriptions.pas` на нужный `.tsv` файл.
4. Отдельно решить вопрос с Detailed Description для всей библиотеки
   (см. пункт выше) — обсудить, продолжать ли точечным веб-поиском или
   заводить DigiKey API-ключ.
5. Разобрать накопленные `digikey_missed_*` и `digikey_needs_verification_*`
   списки.
