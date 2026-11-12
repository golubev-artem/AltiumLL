{ ------------------------------------------------------------------
  Gen_NEG5V_A.pas  -  пилот: генерация узла -5V_A (RSDN_RCVR_SHLD rev 2.1)
  Altium Designer 26, DelphiScript.

  Схема:
    +12V (после D4) -> SGM3209YS8G (инвертирующий насос, ~1 МГц, RSET 82k)
                    -> NEG_CP (около -11.5 В) -> ADP7182AUJZ-5.0-R7 -> -5V_A
    EN насоса: 10k на +3V3 (предел EN 6 В, на IN подключать нельзя).
    EN LDO: на VIN (так в даташите ADP7182: "for automatic startup, connect EN to VIN").

  Соединения сделаны короткими проводами от конца каждого вывода
  с меткой цепи или портом питания на конце. Связность от этого полная,
  а красивую разводку проводов по листу скрипт не делает.

  Порядок запуска:
    1. Создать пустой лист (File > New > Schematic), сохранить его и сделать активным.
    2. DXP > Run Script > Gen_NEG5V_A.pas > процедура GenerateNeg5VA.
    3. Посмотреть лог Gen_NEG5V_A_log.txt рядом с листом,
       затем Compile и проверить цепи в панели Navigator.
  ------------------------------------------------------------------ }

Const
    { библиотека SamacSys: скрипт берёт первый существующий путь }
    SamacLib1 = 'C:\documents\Altium\AltiumLL\SamacSys.SchLib';
    SamacLib2 = 'D:\golubev\Altium\AltiumLL\SamacSys.SchLib';

    { пассивные: Celestial Library, локальные SchLib/PcbLib (без SQL-базы) }
    CelRoot   = 'C:\altium-library\';
    ResLibRel = 'symbols\Passives\SCH - PASSIVES - RESISTOR.SCHLIB';
    CapLibRel = 'symbols\Passives\SCH - PASSIVES - CAPACITOR.SCHLIB';
    ResRef    = 'Resistor';
    CapRef    = 'Capacitor';
    FpCapDir  = 'footprints\Capacitor - MLCC\PCB - CAPACITOR - MLCC - ';
    FpResDir  = 'footprints\Resistor - Chip\PCB - RESISTOR - CHIP - ';

    StubMils  = 100;   { длина провода от конца вывода до метки }

Var
    Doc     : ISch_Document;
    LogF    : TextFile;
    SamacLib, PassLib, ResLib, CapLib : String;
    ErrCount : Integer;

{ ---------------- служебное ---------------- }
Procedure Log(S : String);
Begin
    WriteLn(LogF, S);
End;

Function FirstExisting(A, B : String) : String;
Begin
    Result := '';
    If FileExists(A) Then Result := A
    Else If FileExists(B) Then Result := B;
End;

Procedure Reg(Obj : ISch_GraphicalObject);
Begin
    Doc.RegisterSchObjectInContainer(Obj);
    SchServer.RobotManager.SendMessage(Doc.I_ObjectAddress, c_BroadCast,
        SCHM_PrimitiveRegistration, Obj.I_ObjectAddress);
End;

Procedure AddWire(X1, Y1, X2, Y2 : Integer);   { координаты в TCoord }
Var W : ISch_Wire;
Begin
    W := SchServer.SchObjectFactory(eWire, eCreate_Default);
    W.Location := Point(X1, Y1);
    W.InsertVertex := 1;
    W.SetState_Vertex(1, Point(X1, Y1));
    W.InsertVertex := 2;
    W.SetState_Vertex(2, Point(X2, Y2));
    Reg(W);
End;

Procedure AddNetLabel(X, Y : Integer; Name : String);
Var L : ISch_NetLabel;
Begin
    L := SchServer.SchObjectFactory(eNetLabel, eCreate_Default);
    L.Text := Name;
    L.MoveToXY(X, Y);
    Reg(L);
End;

Procedure AddPower(X, Y : Integer; Name : String; IsGnd : Boolean; Dir : Integer);
Var P : ISch_PowerObject;
Begin
    P := SchServer.SchObjectFactory(ePowerObject, eCreate_Default);
    P.Text := Name;
    If IsGnd Then P.Style := ePowerGndPower Else P.Style := ePowerBar;
    P.ShowNetName := True;
    P.Location := Point(X, Y);
    { порт смотрит наружу от вывода: Dir 0=вправо,1=вверх,2=влево,3=вниз }
    If Dir = 0 Then P.Orientation := eRotate0
    Else If Dir = 1 Then P.Orientation := eRotate90
    Else If Dir = 2 Then P.Orientation := eRotate180
    Else P.Orientation := eRotate270;
    If IsGnd Then P.Orientation := eRotate270;   { земля всегда вниз }
    Reg(P);
End;

Procedure AddNoErc(X, Y : Integer);
Var N : ISch_NoERC;
Begin
    N := SchServer.SchObjectFactory(eNoERC, eCreate_Default);
    N.Location := Point(X, Y);
    Reg(N);
End;

Function AskLib(Title : String) : String;
Var D : TOpenDialog;
Begin
    Result := '';
    D := TOpenDialog.Create(Nil);
    Try
        D.Title  := Title;
        D.Filter := 'Altium libraries (*.IntLib;*.SchLib)|*.IntLib;*.SchLib';
        If D.Execute Then Result := D.FileName;
    Finally
        D.Free;
    End;
End;

{ ---------------- компонент ---------------- }
Function FindCompAt(X, Y : Integer) : ISch_Component;
Var It : ISch_Iterator; C : ISch_Component;
Begin
    Result := Nil;
    It := Doc.SchIterator_Create;
    It.AddFilter_ObjectSet(MkSet(eSchComponent));
    C := It.FirstSchObject;
    While C <> Nil Do
    Begin
        If (C.Location.X = X) And (C.Location.Y = Y) Then Result := C;
        C := It.NextSchObject;
    End;
    Doc.SchIterator_Destroy(It);
End;

Function Place(LibRef, LibPath, Des, Value : String; XMil, YMil, Rot : Integer) : ISch_Component;
Var X, Y : Integer; It : ISch_Iterator; Par : ISch_Parameter; C : ISch_Component;
Begin
    X := MilsToCoord(XMil); Y := MilsToCoord(YMil);
    IntegratedLibraryManager.PlaceLibraryComponent(LibRef, LibPath,
        'Designator=' + Des + '|Orientation=' + IntToStr(Rot) +
        '|Location.X=' + IntToStr(X) + '|Location.Y=' + IntToStr(Y));
    C := FindCompAt(X, Y);
    If C = Nil Then
    Begin
        Log('ОШИБКА: не поставился ' + Des + ' (' + LibRef + ' из ' + LibPath + ')');
        Inc(ErrCount);
        Result := Nil;
        Exit;
    End;
    C.Designator.Text := Des;
    If Value <> '' Then
    Begin
        C.Comment.Text := Value;
        It := C.SchIterator_Create;
        It.AddFilter_ObjectSet(MkSet(eParameter));
        Par := It.FirstSchObject;
        While Par <> Nil Do
        Begin
            If UpperCase(Par.Name) = 'VALUE' Then Par.Text := Value;
            Par := It.NextSchObject;
        End;
        C.SchIterator_Destroy(It);
    End;
    Log('Поставлен ' + Des + ' = ' + LibRef + ' ' + Value);
    Result := C;
End;

{ Простой двухвыводной символ прямо на листе: на случай, если нет библиотеки пассивов.
  Корпус вертикальный, вывод 1 сверху, вывод 2 снизу. Футпринт не привязан. }
Function MakePassive(Kind, Des, Value : String; XMil, YMil : Integer) : ISch_Component;
Var C : ISch_Component; R : ISch_Rectangle; P : ISch_Pin; X, Y : Integer;
Begin
    X := MilsToCoord(XMil); Y := MilsToCoord(YMil);
    C := SchServer.SchObjectFactory(eSchComponent, eCreate_Default);
    C.CurrentPartID := 1;
    C.DisplayMode   := 0;
    C.LibReference  := Kind + '_GEN';
    C.ComponentDescription := 'Generated by Gen_NEG5V_A.pas';
    C.Location := Point(X, Y);
    C.Designator.Text := Des;
    C.Designator.Location := Point(X + MilsToCoord(80), Y + MilsToCoord(40));
    C.Comment.Text := Value;
    C.Comment.IsHidden := False;
    C.Comment.Location := Point(X + MilsToCoord(80), Y - MilsToCoord(60));

    R := SchServer.SchObjectFactory(eRectangle, eCreate_Default);
    R.Location := Point(X - MilsToCoord(30), Y - MilsToCoord(100));
    R.Corner   := Point(X + MilsToCoord(30), Y + MilsToCoord(100));
    R.IsSolid  := False;
    R.OwnerPartId := 1;
    C.AddSchObject(R);

    P := SchServer.SchObjectFactory(ePin, eCreate_Default);
    P.Designator := '1'; P.Name := '1';
    P.Location := Point(X, Y + MilsToCoord(100));
    P.Orientation := eRotate90;
    P.PinLength := MilsToCoord(100);
    P.ShowName := False; P.ShowDesignator := False;
    P.OwnerPartId := 1;
    C.AddSchObject(P);

    P := SchServer.SchObjectFactory(ePin, eCreate_Default);
    P.Designator := '2'; P.Name := '2';
    P.Location := Point(X, Y - MilsToCoord(100));
    P.Orientation := eRotate270;
    P.PinLength := MilsToCoord(100);
    P.ShowName := False; P.ShowDesignator := False;
    P.OwnerPartId := 1;
    C.AddSchObject(P);

    Reg(C);
    Log('Нарисован ' + Des + ' = ' + Kind + '_GEN ' + Value + ' (без футпринта)');
    Result := C;
End;

{ Привязка футпринта из PcbLib Celestial. Ошибка не фатальна: пишется в лог. }
Procedure AddFootprint(C : ISch_Component; FpName, FpLib : String);
Var Impl : ISch_Implementation;
Begin
    If C = Nil Then Exit;
    If Not FileExists(FpLib) Then
    Begin
        Log('  ВНИМАНИЕ: нет файла футпринта ' + FpLib);
        Exit;
    End;
    Try
        Impl := C.AddSchImplementation;
        Impl.ClearAllDatafileLinks;
        Impl.Description := 'Footprint';
        Impl.ModelName   := FpName;
        Impl.ModelType   := 'PCBLIB';
        Impl.AddDataFileLink(FpName, FpLib, 'PCBLIB');
        Impl.IsCurrent   := True;
        Log('  футпринт ' + FpName);
    Except
        Log('  ОШИБКА: не удалось привязать футпринт ' + FpName + ' - привяжи вручную');
        Inc(ErrCount);
    End;
End;

{ Пассивка: Kind 'R'/'C', Pkg - типоразмер ('0402','0805','1206').
  Из Celestial, если библиотека найдена, иначе символ рисуется на листе. }
Function Passive(Kind, Des, Value, Pkg : String; XMil, YMil : Integer) : ISch_Component;
Var FpName, FpLib, Metric : String;
Begin
    If Pkg = '0402' Then Metric := '0402_1005'
    Else If Pkg = '0603' Then Metric := '0603_1608'
    Else If Pkg = '0805' Then Metric := '0805_2012'
    Else Metric := '1206_3216';
    If Kind = 'R' Then
    Begin
        FpName := 'RES ' + Metric;
        FpLib  := CelRoot + FpResDir + FpName + '.PCBLIB';
    End
    Else
    Begin
        FpName := 'CAP ' + Metric;
        FpLib  := CelRoot + FpCapDir + FpName + '.PCBLIB';
    End;

    If (Kind = 'R') And (ResLib <> '') Then
        Result := Place(ResRef, ResLib, Des, Value, XMil, YMil, 1)
    Else If (Kind = 'C') And (CapLib <> '') Then
        Result := Place(CapRef, CapLib, Des, Value, XMil, YMil, 1)
    Else
        Result := MakePassive(Kind, Des, Value, XMil, YMil);
    AddFootprint(Result, FpName, FpLib);
End;

{ Подключение вывода. Net: имя цепи; Kind: 'N' метка, 'P' порт питания,
  'G' земля, 'X' вывод не подключён (No ERC). Вывод ищется по номеру (Designator). }
Procedure Connect(C : ISch_Component; PinNum, Net : String; Kind : String);
Var It : ISch_Iterator; Pin : ISch_Pin;
    Cx, Cy, N, Bx, By, Ex, Ey, Hx, Hy, Dir, Dx, Dy, Sx, Sy : Integer;
    Found : Boolean;
Begin
    If C = Nil Then Exit;
    { центр масс оснований выводов: нужен, чтобы понять, какой конец вывода внешний }
    Cx := 0; Cy := 0; N := 0;
    It := C.SchIterator_Create;
    It.AddFilter_ObjectSet(MkSet(ePin));
    Pin := It.FirstSchObject;
    While Pin <> Nil Do
    Begin
        Cx := Cx + Pin.Location.X; Cy := Cy + Pin.Location.Y; Inc(N);
        Pin := It.NextSchObject;
    End;
    If N > 0 Then Begin Cx := Cx Div N; Cy := Cy Div N; End;

    Found := False;
    Pin := It.FirstSchObject;
    While (Pin <> Nil) And (Not Found) Do
    Begin
        If Pin.Designator = PinNum Then
        Begin
            Found := True;
            Dx := 1; Dy := 0; Dir := 0;
            If Pin.Orientation = eRotate90  Then Begin Dx :=  0; Dy :=  1; Dir := 1; End;
            If Pin.Orientation = eRotate180 Then Begin Dx := -1; Dy :=  0; Dir := 2; End;
            If Pin.Orientation = eRotate270 Then Begin Dx :=  0; Dy := -1; Dir := 3; End;
            Bx := Pin.Location.X; By := Pin.Location.Y;
            Ex := Bx + Dx * Pin.PinLength; Ey := By + Dy * Pin.PinLength;
            { внешний конец - тот, что дальше от центра компонента }
            If (Abs(Ex - Cx) + Abs(Ey - Cy)) >= (Abs(Bx - Cx) + Abs(By - Cy)) Then
            Begin Hx := Ex; Hy := Ey; End
            Else
            Begin Hx := Bx; Hy := By; Dx := -Dx; Dy := -Dy; Dir := (Dir + 2) Mod 4; End;

            Log('  ' + C.Designator.Text + '.' + PinNum + ' (' + Pin.Name + ') -> ' + Net +
                '  @' + IntToStr(CoordToMils(Hx)) + ',' + IntToStr(CoordToMils(Hy)) + ' mil');

            If Kind = 'X' Then
                AddNoErc(Hx, Hy)
            Else
            Begin
                Sx := Hx + Dx * MilsToCoord(StubMils);
                Sy := Hy + Dy * MilsToCoord(StubMils);
                AddWire(Hx, Hy, Sx, Sy);
                If Kind = 'N' Then AddNetLabel(Sx, Sy, Net)
                Else If Kind = 'P' Then AddPower(Sx, Sy, Net, False, Dir)
                Else If Kind = 'G' Then AddPower(Sx, Sy, Net, True, Dir);
            End;
        End;
        Pin := It.NextSchObject;
    End;
    C.SchIterator_Destroy(It);
    If Not Found Then
    Begin
        Log('ОШИБКА: у ' + C.Designator.Text + ' нет вывода ' + PinNum);
        Inc(ErrCount);
    End;
End;

{ Двухвыводная пассивка: вывод 1 -> NetA, вывод 2 -> NetB }
Procedure Two(C : ISch_Component; NetA : String; KindA : String; NetB : String; KindB : String);
Begin
    Connect(C, '1', NetA, KindA);
    Connect(C, '2', NetB, KindB);
End;

{ ---------------- главная процедура ---------------- }
Procedure GenerateNeg5VA;
Var U1, U2, C : ISch_Component;
    LogName : String;
Begin
    Doc := SchServer.GetCurrentSchDocument;
    If Doc = Nil Then Begin ShowMessage('Нет активного листа SchDoc.'); Exit; End;

    SamacLib := FirstExisting(SamacLib1, SamacLib2);
    ResLib := FirstExisting(CelRoot + ResLibRel, '');
    CapLib := FirstExisting(CelRoot + CapLibRel, '');
    If SamacLib = '' Then Begin ShowMessage('Не найден SamacSys.SchLib - поправь SamacLib1/2.'); Exit; End;

    LogName := ExtractFilePath(Doc.DocumentName) + 'Gen_NEG5V_A_log.txt';
    AssignFile(LogF, LogName); Rewrite(LogF);
    Log('Gen_NEG5V_A  ' + DateTimeToStr(Now));
    Log('SamacSys: ' + SamacLib);
    If (ResLib <> '') And (CapLib <> '') Then Log('Пассивы : Celestial, ' + CelRoot)
    Else Log('Пассивы : Celestial не найдена, символы R/C рисуются на листе');
    ErrCount := 0;

    SchServer.ProcessControl.PreProcess(Doc, '');
    Try
        { --- насос SGM3209 --- }
        U1 := Place('SGM3209YS8G', SamacLib, 'U1', 'SGM3209YS8G/TR', 2000, 4000, 0);
        Connect(U1, '8', '+12V',     'P');    { IN }
        Connect(U1, '3', 'GND',      'G');
        Connect(U1, '2', 'NEG5_CFP', 'N');    { CFLY+ }
        Connect(U1, '4', 'NEG5_CFN', 'N');    { CFLY- }
        Connect(U1, '5', 'NEG_CP',   'N');    { OUT, около -11.5 В }
        Connect(U1, '6', 'NEG5_EN',  'N');    { EN }
        Connect(U1, '7', 'NEG5_RP',  'N');    { RP }
        Connect(U1, '1', '',         'X');    { NC }

        { --- LDO ADP7182 фиксированный -5.0 В --- }
        U2 := Place('ADP7182AUJZ-5.0-R7', SamacLib, 'U2', 'ADP7182AUJZ-5.0-R7', 4500, 4000, 0);
        Connect(U2, '2', 'NEG_CP', 'N');      { VIN }
        Connect(U2, '3', 'NEG_CP', 'N');      { EN = VIN }
        Connect(U2, '1', 'GND',    'G');
        Connect(U2, '5', '-5V_A',  'P');      { VOUT }
        Connect(U2, '4', '',       'X');      { NC: "do not connect" }

        { --- пассивные: вертикально (Orientation=1), в ряд под микросхемами --- }
        C := Passive('C', 'C1', '10uF 25V X7R 1206', '1206', 1000, 2400);
        Two(C, '+12V', 'P', 'GND', 'G');                       { CIN }
        C := Passive('C', 'C2', '100nF 50V X7R 0402', '0402', 1600, 2400);
        Two(C, '+12V', 'P', 'GND', 'G');                       { CBP }
        C := Passive('C', 'C3', '10uF 25V X7R 1206', '1206', 2200, 2400);
        Two(C, 'NEG5_CFP', 'N', 'NEG5_CFN', 'N');              { CFLY }
        C := Passive('C', 'C4', '10uF 25V X7R 1206', '1206', 2800, 2400);
        Two(C, 'GND', 'G', 'NEG_CP', 'N');                     { COUT насоса }
        C := Passive('R', 'R1', '10k 1% 0402', '0402', 3400, 2400);
        Two(C, '+3V3', 'P', 'NEG5_EN', 'N');                   { EN pull-up }
        C := Passive('R', 'R2', '82k 1% 0402', '0402', 4000, 2400);
        Two(C, 'NEG5_RP', 'N', 'GND', 'G');                    { RSET ~1 МГц }
        C := Passive('C', 'C5', '2.2uF 25V X7R 0805', '0805', 4600, 2400);
        Two(C, 'GND', 'G', 'NEG_CP', 'N');                     { CIN LDO }
        C := Passive('C', 'C6', '2.2uF 25V X7R 0805', '0805', 5200, 2400);
        Two(C, 'GND', 'G', '-5V_A', 'P');                      { COUT LDO }
    Finally
        SchServer.ProcessControl.PostProcess(Doc, '');
    End;

    Log('');
    Log('Ошибок: ' + IntToStr(ErrCount));
    CloseFile(LogF);
    Doc.GraphicallyInvalidate;
    ShowMessage('Готово, ошибок: ' + IntToStr(ErrCount) + #13#10 + 'Лог: ' + LogName);
End;
