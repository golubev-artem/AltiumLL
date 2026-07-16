{ ------------------------------------------------------------------
  UpdateDescriptions.pas

  Applies Description / Detailed Description values from a tab-
  separated data file to components in the currently active SchLib
  document (SamacSys.SchLib), using DigiKey data collected offline.

  Data file format (UTF-8, tab-separated, no header row):
    DesignItemID <TAB> Description <TAB> DetailedDescription

  DetailedDescription may be left empty (row ends right after the second
  TAB, or the third field is blank) - in that case only Description is
  updated for that component, and any existing/added Detailed Description
  parameter is left untouched.

  Usage:
    1. Open SamacSys.SchLib (BACKUP_TEST copy) in Altium Designer so it
       is the active document.
    2. Adjust DataFilePath / LogFolder below if needed.
    3. Run this script (DXP > Run Script, or from the Scripting panel),
       procedure ApplyDigikeyDescriptions.
    4. Review the report dialog and the generated log file, then save
       the library manually (Ctrl+S).

  Notes:
    - Only components found in the data file are touched. Everything
      else in the library is left exactly as-is.
    - ComponentDescription is overwritten unconditionally for matched
      rows.
    - Detailed Description is added as a new parameter if missing, or
      updated in place if a parameter with that name already exists.
    - Every run writes a timestamped log file (update_log_<date_time>.txt)
      into LogFolder recording, per component: old Description,
      new Description, and the Detailed Description value that was
      added or updated.
  ------------------------------------------------------------------ }

Const
    DataFilePath = 'D:\golubev\Altium\AltiumLL\BACKUP_TEST\digikey_updates_part00.tsv';
    LogFolder    = 'D:\golubev\Altium\AltiumLL\BACKUP_TEST\';

Procedure ApplyDigikeyDescriptions;
Var
    CurrentLib     : ISch_Lib;
    CompIterator   : ISch_Iterator;
    ParamIterator  : ISch_Iterator;
    Component      : ISch_Component;
    Param          : ISch_Parameter;
    F              : TextFile;
    LogF           : TextFile;
    LogFileName    : WideString;
    RunStamp       : WideString;
    Line           : WideString;
    TabPos1        : Integer;
    TabPos2        : Integer;
    KeyId          : WideString;
    NewDesc        : WideString;
    NewDetailed    : WideString;
    OldDesc        : WideString;
    DetailedAction : WideString;
    Updates        : TStringList;
    i              : Integer;
    MatchedCount   : Integer;
    NotFoundList   : TStringList;
    FoundDetailed  : Boolean;
Begin
    CurrentLib := SchServer.GetCurrentSchDocument;
    If CurrentLib = Nil Then
    Begin
        ShowMessage('No active SchLib document. Open SamacSys.SchLib first.');
        Exit;
    End;

    If Not FileExists(DataFilePath) Then
    Begin
        ShowMessage('Data file not found: ' + DataFilePath);
        Exit;
    End;

    RunStamp := FormatDateTime('yyyy-mm-dd_hh-nn-ss', Now);
    LogFileName := LogFolder + 'update_log_' + RunStamp + '.txt';
    AssignFile(LogF, LogFileName);
    Rewrite(LogF);
    WriteLn(LogF, 'UpdateDescriptions run: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
    WriteLn(LogF, 'Data file: ' + DataFilePath);
    WriteLn(LogF, '');
    WriteLn(LogF, 'DesignItemID' + #9 + 'OldDescription' + #9 + 'NewDescription' + #9 +
                  'DetailedDescriptionAction' + #9 + 'DetailedDescriptionValue');

    { Load the TSV data file into memory: Updates[i] = 'DesignItemID=Description||DetailedDescription' }
    Updates := TStringList.Create;
    AssignFile(F, DataFilePath);
    Reset(F);
    While Not Eof(F) Do
    Begin
        ReadLn(F, Line);
        If Length(Trim(Line)) = 0 Then Continue;

        TabPos1 := Pos(#9, Line);
        If TabPos1 = 0 Then Continue;
        TabPos2 := Pos(#9, Copy(Line, TabPos1 + 1, Length(Line)));
        If TabPos2 = 0 Then
        Begin
            { No third field at all: Description only, no Detailed Description }
            KeyId       := Copy(Line, 1, TabPos1 - 1);
            NewDesc     := Copy(Line, TabPos1 + 1, Length(Line));
            NewDetailed := '';
        End
        Else
        Begin
            TabPos2 := TabPos1 + TabPos2;
            KeyId       := Copy(Line, 1, TabPos1 - 1);
            NewDesc     := Copy(Line, TabPos1 + 1, TabPos2 - TabPos1 - 1);
            NewDetailed := Copy(Line, TabPos2 + 1, Length(Line));
        End;

        Updates.Values[KeyId] := NewDesc + '||' + NewDetailed;
    End;
    CloseFile(F);

    NotFoundList := TStringList.Create;
    MatchedCount := 0;

    { Walk every component currently in the library }
    CompIterator := CurrentLib.SchLibIterator_Create;
    CompIterator.AddFilter_ObjectSet(MkSet(eSchComponent));
    Try
        Component := CompIterator.FirstSchObject;
        While Component <> Nil Do
        Begin
            i := Updates.IndexOfName(Component.LibReference);
            If i >= 0 Then
            Begin
                NewDesc     := Copy(Updates.ValueFromIndex[i], 1, Pos('||', Updates.ValueFromIndex[i]) - 1);
                NewDetailed := Copy(Updates.ValueFromIndex[i], Pos('||', Updates.ValueFromIndex[i]) + 2, Length(Updates.ValueFromIndex[i]));

                { Description }
                OldDesc := Component.ComponentDescription;
                Component.ComponentDescription := NewDesc;

                { Detailed Description parameter: update if present, else add new -
                  but only if the data file actually supplied a non-empty value }
                If Length(Trim(NewDetailed)) = 0 Then
                    DetailedAction := 'SKIPPED (no data)'
                Else
                Begin
                    FoundDetailed := False;
                    ParamIterator := Component.SchIterator_Create;
                    ParamIterator.AddFilter_ObjectSet(MkSet(eParameter));
                    Try
                        Param := ParamIterator.FirstSchObject;
                        While Param <> Nil Do
                        Begin
                            If CompareText(Param.Name, 'Detailed Description') = 0 Then
                            Begin
                                Param.Text := NewDetailed;
                                FoundDetailed := True;
                            End;
                            Param := ParamIterator.NextSchObject;
                        End;
                    Finally
                        Component.SchIterator_Destroy(ParamIterator);
                    End;

                    If FoundDetailed Then
                        DetailedAction := 'UPDATED'
                    Else
                    Begin
                        Param := SchServer.SchObjectFactory(eParameter, eCreate_Default);
                        Param.Name       := 'Detailed Description';
                        Param.Text       := NewDetailed;
                        Param.OwnerPartId := -1;
                        Param.IsHidden   := True;
                        Component.AddSchObject(Param);
                        DetailedAction := 'ADDED';
                    End;
                End;

                WriteLn(LogF, Component.LibReference + #9 + OldDesc + #9 + NewDesc + #9 +
                              DetailedAction + #9 + NewDetailed);

                Inc(MatchedCount);
            End;

            Component := CompIterator.NextSchObject;
        End;
    Finally
        CurrentLib.SchIterator_Destroy(CompIterator);
    End;

    { Report which data-file rows never matched a component in the library }
    For i := 0 To Updates.Count - 1 Do
    Begin
        KeyId := Updates.Names[i];
        CompIterator := CurrentLib.SchLibIterator_Create;
        CompIterator.AddFilter_ObjectSet(MkSet(eSchComponent));
        Try
            Component := CompIterator.FirstSchObject;
            While (Component <> Nil) And (CompareText(Component.LibReference, KeyId) <> 0) Do
                Component := CompIterator.NextSchObject;
            If Component = Nil Then
                NotFoundList.Add(KeyId);
        Finally
            CurrentLib.SchIterator_Destroy(CompIterator);
        End;
    End;

    WriteLn(LogF, '');
    WriteLn(LogF, 'Summary: ' + IntToStr(MatchedCount) + ' component(s) updated, ' +
                  IntToStr(NotFoundList.Count) + ' data-file row(s) not found in library.');
    If NotFoundList.Count > 0 Then
    Begin
        WriteLn(LogF, 'Not found in library:');
        For i := 0 To NotFoundList.Count - 1 Do
            WriteLn(LogF, '  ' + NotFoundList[i]);
    End;
    CloseFile(LogF);

    CurrentLib.GraphicallyInvalidate;

    ShowMessage('Updated ' + IntToStr(MatchedCount) + ' component(s).' + #13#10 +
                'Rows in data file not found in library: ' + IntToStr(NotFoundList.Count) + #13#10 +
                'Log written to: ' + LogFileName + #13#10 +
                'Remember to save the library (Ctrl+S).');

    Updates.Free;
    NotFoundList.Free;
End;
