unit uInfoForm;

{ Developer information window (opens at startup; I or F1 brings it back; 1..8 switch tabs).
  Tabs:
    Overview     project, architecture, pipeline, hotkeys and a parameter dump
    Performance  live fps / vsync, frame history graph, pipeline timings
    Threads      thread and band controls, per-worker and per-band cost
    Layers       switch single layers on/off, CPU cost of each layer
    Objects      live counts, sizes, memory, SDL3 and build information
    Palette      every colour used, with its hex code
    Time of day  morning / day / night / auto, fade settings, live values
    Export       PNG / SVG / GIF / MP4 of the main picture and every layer
  Built in code, no .lfm. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, StrUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls,
  ComCtrls, Spin, Clipbrd, LCLType, BGRABitmap, BGRABitmapTypes,
  CheckLst, EditBtn, LCLIntf, uRenderPool, uCityScene, uFrameRenderer, uExportJob, uMFVideo;

type

  { TInfoForm }

  TInfoForm = class(TForm)
  private
    FPages: TPageControl;
    FOverview: TMemo;
    FPerfBox, FThreadBox, FPaletteBox: TPaintBox;
    { export tab }
    FExpFolder: TDirectoryEdit;
    FExpW, FExpH, FExpFrames, FExpFps, FExpKbps: TSpinEdit;
    FExpPng, FExpSeq, FExpSvg, FExpGif, FExpMp4, FExpHw: TCheckBox;
    FExpTargets: TCheckListBox;
    FExpInfo: TLabel;
    FExpProgress: TProgressBar;
    FExpLog: TMemo;
    FExpRun, FExpCancel: TButton;
    FExpCancelled, FExpBusy: Boolean;
    FLayerList, FObjList, FTimeList: TListView;
    FAutoSpin, FFadeSpin: TSpinEdit;
    FExpLive, FExpMorning, FExpDay, FExpNight: TCheckBox;
    FThreadSpin, FBandSpin: TSpinEdit;
    FVSyncCheck: TCheckBox;
    FBtnPause, FBtnCaption: TButton;
    FStatus: TLabel;
    FTimer: TTimer;
    FUpdating: Boolean;
    FBuf: TBitmap;        // GDI back buffer of the live panels
    FPaintMs: Double;     // last live panel paint (main thread time)
    FAdaptiveCheck: TCheckBox;
    FOrder: Integer;  // increasing Left so left-aligned controls keep creation order
    function AddTab(const ACaption: string): TTabSheet;
    function AddBar(AParent: TWinControl): TPanel;
    function AddButton(AParent: TWinControl; const ACaption: string;
      AHandler: TNotifyEvent): TButton;
    function AddLabel(AParent: TWinControl; const ACaption: string): TLabel;
    function AddList(AParent: TWinControl): TListView;
    procedure AddCol(LV: TListView; const ACaption: string; AWidth: Integer);
    procedure BuildUI;
    procedure FillLayers;
    procedure RefreshLayers;
    procedure RefreshObjects;
    procedure RefreshTime;
    procedure TimeModeClick(Sender: TObject);
    procedure SeasonClick(Sender: TObject);
    procedure TimeSpinChange(Sender: TObject);
    procedure RefreshOverview;
    procedure RefreshControls;
    function OverviewText: string;
    function ReportText: string;
    procedure TimerTick(Sender: TObject);
    procedure PageChange(Sender: TObject);
    function Buffer(ABox: TPaintBox): TCanvas;
    procedure AdaptiveClick(Sender: TObject);
    procedure PerfPaint(Sender: TObject);
    procedure ThreadPaint(Sender: TObject);
    procedure PalettePaint(Sender: TObject);
    procedure LayerChecked(Sender: TObject; Item: TListItem);
    procedure AllOnClick(Sender: TObject);
    procedure AllOffClick(Sender: TObject);
    procedure SoloClick(Sender: TObject);
    procedure ThreadsChange(Sender: TObject);
    procedure BandsChange(Sender: TObject);
    procedure VSyncClick(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure PauseClick(Sender: TObject);
    procedure CaptionClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure CopyClick(Sender: TObject);
    procedure RefreshClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure BuildExportTab(Tab: TTabSheet);
    function AddSpin(AParent: TWinControl; AMin, AMax, AValue: Integer): TSpinEdit;
    function AddCheck(AParent: TWinControl; const ACaption: string; AChecked: Boolean): TCheckBox;
    procedure ExpEstimate(Sender: TObject);
    procedure ExpWindowSize(Sender: TObject);
    procedure ExpHalfSize(Sender: TObject);
    procedure ExpAllTargets(Sender: TObject);
    procedure ExpNoTargets(Sender: TObject);
    procedure ExpMainOnly(Sender: TObject);
    procedure ExpOpenFolder(Sender: TObject);
    procedure ExpRunClick(Sender: TObject);
    procedure ExpCancelClick(Sender: TObject);
    procedure ExpProgressCb(const AMessage: string; ADone, ATotal: Integer; var ACancel: Boolean);
    procedure FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure InfoClose(Sender: TObject; var CloseAction: TCloseAction);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ShowExportTab;
  end;

var
  InfoForm: TInfoForm;

implementation

uses
  uSDLView;

const
  TabCount = 8;

function Ms(V: Double): string;
begin
  Result := FormatFloat('0.00', V) + ' ms';
end;

function KB(V: Int64): string;
begin
  if V >= 1024 * 1024 then
    Result := FormatFloat('0.0', V / (1024 * 1024)) + ' MB'
  else
    Result := FormatFloat('0.0', V / 1024) + ' KB';
end;

{ worker colours for the thread charts }
function WorkerColor(I: Integer): TColor;
begin
  Result := BGRAToColor(HSLAToBGRA(HSLA((I * 9973) mod 65536, 40000, 30000)));
end;

{ TInfoForm }

constructor TInfoForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Caption := 'New York Town Papercut SDL3 - Developer info';
  Width := Scale96ToForm(780);
  Height := Scale96ToForm(820);
  Position := poDesigned;
  KeyPreview := True;
  OnKeyDown := @FormKey;
  OnClose := @InfoClose;
  BuildUI;
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 250;
  FTimer.OnTimer := @TimerTick;
  RefreshOverview;
  RefreshControls;
end;

destructor TInfoForm.Destroy;
begin
  FBuf.Free;
  inherited Destroy;
end;

function TInfoForm.AddTab(const ACaption: string): TTabSheet;
begin
  Result := FPages.AddTabSheet;
  Result.Caption := ACaption;
end;

function TInfoForm.AddBar(AParent: TWinControl): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := AParent;
  Result.Align := alTop;
  Result.Height := Scale96ToForm(34);
  Result.BevelOuter := bvNone;
  Inc(FOrder);
  Result.Top := FOrder * 1000;  // top-aligned rows keep creation order
end;

function TInfoForm.AddButton(AParent: TWinControl; const ACaption: string;
  AHandler: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.AutoSize := True;
  Result.Align := alLeft;
  Result.BorderSpacing.Around := 3;
  Inc(FOrder);
  Result.Left := FOrder * 1000;
  Result.OnClick := AHandler;
end;

function TInfoForm.AddLabel(AParent: TWinControl; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Align := alLeft;
  Result.Layout := tlCenter;
  Result.BorderSpacing.Left := 8;
  Result.BorderSpacing.Right := 4;
  Inc(FOrder);
  Result.Left := FOrder * 1000;
end;

function TInfoForm.AddList(AParent: TWinControl): TListView;
begin
  Result := TListView.Create(Self);
  Result.Parent := AParent;
  Result.Align := alClient;
  Result.ViewStyle := vsReport;
  Result.ReadOnly := True;
  Result.RowSelect := True;
  Result.GridLines := True;
end;

procedure TInfoForm.AddCol(LV: TListView; const ACaption: string; AWidth: Integer);
var
  Col: TListColumn;
begin
  Col := LV.Columns.Add;
  Col.Caption := ACaption;
  Col.Width := Scale96ToForm(AWidth);
end;

procedure TInfoForm.BuildUI;
var
  Bar, TopBar: TPanel;
  Tab: TTabSheet;
begin
  { bottom bar with the main window controls }
  Bar := TPanel.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alBottom;
  Bar.Height := Scale96ToForm(36);
  Bar.BevelOuter := bvNone;
  Bar.BorderSpacing.Around := 2;
  FBtnPause := AddButton(Bar, 'Pause', @PauseClick);
  FBtnCaption := AddButton(Bar, 'Hide caption', @CaptionClick);
  AddButton(Bar, 'Save PNG', @SaveClick);
  AddButton(Bar, 'Copy report', @CopyClick);
  AddButton(Bar, 'Close', @CloseClick);
  FStatus := TLabel.Create(Self);
  FStatus.Parent := Bar;
  FStatus.Align := alClient;
  FStatus.Alignment := taRightJustify;
  FStatus.Layout := tlCenter;
  FStatus.BorderSpacing.Right := 8;

  FPages := TPageControl.Create(Self);
  FPages.Parent := Self;
  FPages.Align := alClient;
  FPages.OnChange := @PageChange;

  { 1 Overview }
  Tab := AddTab('Overview');
  TopBar := AddBar(Tab);
  AddButton(TopBar, 'Refresh', @RefreshClick);
  AddButton(TopBar, 'Copy all', @CopyClick);
  FOverview := TMemo.Create(Self);
  FOverview.Parent := Tab;
  FOverview.Align := alClient;
  FOverview.ReadOnly := True;
  FOverview.ScrollBars := ssBoth;
  FOverview.WordWrap := False;
  FOverview.Font.Name := 'Consolas';
  FOverview.Font.Size := 9;

  { 2 Performance }
  Tab := AddTab('Performance');
  TopBar := AddBar(Tab);
  AddButton(TopBar, 'Reset statistics', @ResetClick);
  FVSyncCheck := TCheckBox.Create(Self);
  FVSyncCheck.Parent := TopBar;
  FVSyncCheck.Caption := 'VSync (V)';
  FVSyncCheck.Align := alLeft;
  FVSyncCheck.BorderSpacing.Left := 12;
  Inc(FOrder);
  FVSyncCheck.Left := FOrder * 1000;
  FVSyncCheck.OnClick := @VSyncClick;
  FPerfBox := TPaintBox.Create(Self);
  FPerfBox.Parent := Tab;
  FPerfBox.Align := alClient;
  FPerfBox.OnPaint := @PerfPaint;

  { 3 Threads }
  Tab := AddTab('Threads');
  TopBar := AddBar(Tab);
  AddLabel(TopBar, 'Worker threads');
  FThreadSpin := TSpinEdit.Create(Self);
  FThreadSpin.Parent := TopBar;
  FThreadSpin.Align := alLeft;
  FThreadSpin.BorderSpacing.Around := 4;
  FThreadSpin.MinValue := 1;
  FThreadSpin.MaxValue := MaxThreads;
  Inc(FOrder);
  FThreadSpin.Left := FOrder * 1000;
  FThreadSpin.OnChange := @ThreadsChange;
  AddLabel(TopBar, 'Bands per thread');
  FBandSpin := TSpinEdit.Create(Self);
  FBandSpin.Parent := TopBar;
  FBandSpin.Align := alLeft;
  FBandSpin.BorderSpacing.Around := 4;
  FBandSpin.MinValue := 1;
  FBandSpin.MaxValue := 16;
  Inc(FOrder);
  FBandSpin.Left := FOrder * 1000;
  FBandSpin.OnChange := @BandsChange;
  FAdaptiveCheck := TCheckBox.Create(Self);
  FAdaptiveCheck.Parent := TopBar;
  FAdaptiveCheck.Caption := 'Adaptive bands';
  FAdaptiveCheck.Align := alLeft;
  FAdaptiveCheck.BorderSpacing.Left := 12;
  Inc(FOrder);
  FAdaptiveCheck.Left := FOrder * 1000;
  FAdaptiveCheck.OnClick := @AdaptiveClick;
  FThreadBox := TPaintBox.Create(Self);
  FThreadBox.Parent := Tab;
  FThreadBox.Align := alClient;
  FThreadBox.OnPaint := @ThreadPaint;

  { 4 Layers }
  Tab := AddTab('Layers');
  TopBar := AddBar(Tab);
  AddButton(TopBar, 'All on', @AllOnClick);
  AddButton(TopBar, 'All off', @AllOffClick);
  AddButton(TopBar, 'Solo selected', @SoloClick);
  FLayerList := AddList(Tab);
  FLayerList.Checkboxes := True;
  AddCol(FLayerList, 'Layer', 120);
  AddCol(FLayerList, 'Kind', 100);
  AddCol(FLayerList, 'Shadow', 56);
  AddCol(FLayerList, 'CPU ms', 70);
  AddCol(FLayerList, 'Share', 56);
  AddCol(FLayerList, 'What it draws', 520);
  FillLayers;
  FLayerList.OnItemChecked := @LayerChecked;

  { 5 Objects }
  Tab := AddTab('Objects');
  FObjList := AddList(Tab);
  AddCol(FObjList, 'Item', 170);
  AddCol(FObjList, 'Value', 190);
  AddCol(FObjList, 'Detail', 380);

  { 6 Palette }
  Tab := AddTab('Palette');
  FPaletteBox := TPaintBox.Create(Self);
  FPaletteBox.Parent := Tab;
  FPaletteBox.Align := alClient;
  FPaletteBox.OnPaint := @PalettePaint;

  { 7 Time of day }
  Tab := AddTab('Time of day');
  TopBar := AddBar(Tab);
  AddButton(TopBar, 'Morning (M)', @TimeModeClick).Tag := 0;
  AddButton(TopBar, 'Day (D)', @TimeModeClick).Tag := 1;
  AddButton(TopBar, 'Night (N)', @TimeModeClick).Tag := 2;
  AddButton(TopBar, 'Auto on/off (A)', @TimeModeClick).Tag := -1;
  TopBar := AddBar(Tab);
  AddLabel(TopBar, 'Season');
  AddButton(TopBar, 'Summer (1)', @SeasonClick).Tag := 0;
  AddButton(TopBar, 'Rainy (2)', @SeasonClick).Tag := 1;
  AddButton(TopBar, 'Winter (3)', @SeasonClick).Tag := 2;
  TopBar := AddBar(Tab);
  AddLabel(TopBar, 'Auto: seconds per time of day');
  FAutoSpin := AddSpin(TopBar, 2, 600, 14);
  FAutoSpin.OnChange := @TimeSpinChange;
  AddLabel(TopBar, 'Fade (1/10 s)');
  FFadeSpin := AddSpin(TopBar, 0, 100, 22);
  FFadeSpin.OnChange := @TimeSpinChange;
  FTimeList := AddList(Tab);
  AddCol(FTimeList, 'Item', 150);
  AddCol(FTimeList, 'Value', 150);
  AddCol(FTimeList, 'Detail', 440);

  { 8 Export }
  BuildExportTab(AddTab('Export'));
end;

{ ---------- layers ---------- }

procedure TInfoForm.FillLayers;
var
  Id: TLayerId;
  It: TListItem;
begin
  FUpdating := True;
  try
    FLayerList.Items.BeginUpdate;
    FLayerList.Items.Clear;
    for Id := Low(TLayerId) to High(TLayerId) do
    begin
      It := FLayerList.Items.Add;
      It.Caption := LayerNames[Id];
      It.SubItems.Add(LayerKinds[Id]);
      if LayerDepth[Id] = 0 then
        It.SubItems.Add('-')
      else
        It.SubItems.Add(FormatFloat('0.##', LayerDepth[Id]));
      It.SubItems.Add('');
      It.SubItems.Add('');
      It.SubItems.Add(LayerNotes[Id]);
      It.Checked := View.Scene.LayerOn[Id];
    end;
    FLayerList.Items.EndUpdate;
  finally
    FUpdating := False;
  end;
end;

procedure TInfoForm.RefreshLayers;
var
  Id: TLayerId;
  It: TListItem;
  Total: Double;
begin
  Total := 0;
  for Id := Low(TLayerId) to High(TLayerId) do
    Total := Total + View.Renderer.LayerCpuMs[Id];
  Total := Max(0.001, Total);
  FUpdating := True;
  try
    for Id := Low(TLayerId) to High(TLayerId) do
    begin
      It := FLayerList.Items[Ord(Id)];
      It.SubItems[2] := FormatFloat('0.00', View.Renderer.LayerCpuMs[Id]);
      It.SubItems[3] := FormatFloat('0', View.Renderer.LayerCpuMs[Id] / Total * 100) + ' %';
      if It.Checked <> View.Scene.LayerOn[Id] then
        It.Checked := View.Scene.LayerOn[Id];
    end;
  finally
    FUpdating := False;
  end;
end;

procedure TInfoForm.LayerChecked(Sender: TObject; Item: TListItem);
begin
  if FUpdating or (Item = nil) then Exit;
  View.Scene.LayerOn[TLayerId(Item.Index)] := Item.Checked;
  View.Redraw;
end;

procedure TInfoForm.AllOnClick(Sender: TObject);
var
  Id: TLayerId;
begin
  for Id := Low(TLayerId) to High(TLayerId) do
    View.Scene.LayerOn[Id] := True;
  RefreshLayers;
  View.Redraw;
end;

procedure TInfoForm.AllOffClick(Sender: TObject);
var
  Id: TLayerId;
begin
  for Id := Low(TLayerId) to High(TLayerId) do
    View.Scene.LayerOn[Id] := False;
  RefreshLayers;
  View.Redraw;
end;

{ Only the selected layer (plus the paper background) stays on. }
procedure TInfoForm.SoloClick(Sender: TObject);
var
  Id: TLayerId;
begin
  if FLayerList.Selected = nil then Exit;
  for Id := Low(TLayerId) to High(TLayerId) do
    View.Scene.LayerOn[Id] := (Ord(Id) = FLayerList.Selected.Index) or (Id = lySky);
  RefreshLayers;
  View.Redraw;
end;

{ ---------- objects ---------- }

procedure TInfoForm.RefreshObjects;
var
  Sc: TCityScene;
  R: TFrameRenderer;
  M: TSDLView;

  K: Integer;

  { rows are created once and then only changed text is written }
  procedure Row(const AName, AValue, ADetail: string);
  var
    It: TListItem;
  begin
    if K < FObjList.Items.Count then
      It := FObjList.Items[K]
    else
    begin
      It := FObjList.Items.Add;
      It.SubItems.Add('');
      It.SubItems.Add('');
    end;
    if It.Caption <> AName then It.Caption := AName;
    if It.SubItems[0] <> AValue then It.SubItems[0] := AValue;
    if It.SubItems[1] <> ADetail then It.SubItems[1] := ADetail;
    Inc(K);
  end;

begin
  M := View;
  Sc := M.Scene;
  R := M.Renderer;
  K := 0;
  begin
    Row('Frame (SDL pixels)', Format('%d x %d', [R.Width, R.Height]),
      IfThen(M.FullScreen, 'full screen', 'windowed'));
    Row('Design space', Format('%d x %d', [DesignW, DesignH]), 'size of the reference image');
    Row('Scale', FormatFloat('0.0000', Sc.Scale), 'fit by min(width/1600, height/900)');
    Row('Offset', Format('%s, %s px', [FormatFloat('0', Sc.OffX), FormatFloat('0', Sc.OffY)]),
      'picture is centred in the window');
    Row('Visible x range', Format('%s .. %s', [FormatFloat('0', Sc.VisL), FormatFloat('0', Sc.VisR)]),
      'design px, clouds and birds wrap here');
    Row('Scene time', FormatFloat('0.0', Sc.Time) + ' s', IfThen(M.Paused, 'paused', 'running'));
    Row('Frames presented', IntToStr(M.FrameCount), Format('%d rendered by the pool', [R.Frames]));
    Row('Missed vsync', IntToStr(M.MissedFrames), 'present interval > 1.5 refresh periods');
    Row('Worker threads', IntToStr(R.Threads), Format('%d logical cores in this machine',
      [TThread.ProcessorCount]));
    Row('Bands', Format('%d, about %d px', [R.BandCount, R.BandHeight]),
      Format('%d per thread, taken dynamically', [R.BandsPerThread]));
    Row('Static cut', Ms(Sc.StaticMs), Format('main thread, %d times so far', [Sc.StaticCount]));
    Row('Sprites', IntToStr(Sc.SpriteCount), 'cloud sprites, one per cloud and palette');
    Row('Sprite memory', KB(Sc.SpriteBytes), 'cloud + caption sprites');
    Row('Static bitmaps', KB(Sc.StaticBytes), '6 parts x 3 palettes + 3 light sprites + cutter');
    Row('Band bitmaps', KB(Int64(R.Width) * R.Height * 4), 'one frame, split in bands');
    Row('Season', SeasonNames[Sc.Season], '1 summer, 2 rainy, 3 winter');
    Row('Time of day', ModeNames[Sc.ModeFrom] + IfThen(Sc.ModeFrom <> Sc.ModeTo,
      ' -> ' + ModeNames[Sc.ModeTo], ''), Format('blend %s, night %s, shade %s, auto %s',
      [FormatFloat('0.00', Sc.Blend), FormatFloat('0.00', Sc.Night), FormatFloat('0.00', Sc.Shade),
      IfThen(Sc.AutoCycle, 'on', 'off')]));
    Row('Buildings', '2 rows + 5 landmarks', 'Empire State, Chrysler, One WTC, crane, Liberty');
    Row('Window lights', Format('%d flicker', [Sc.WindowLightCount]),
      'thousands baked in a light sprite, faded in by the night amount');
    Row('Road vehicles', IntToStr(Sc.CarCount), 'sedan, taxi, bus, truck, van; 2 lanes, stop at red');
    Row('Bridge / train', '22 cars + 6 coaches', 'cars both ways, train every 4-9 s');
    Row('Boats / plane / birds', '3 / 1 / 9', 'ferry, tug + barge, sailboat');
    Row('Clouds / stars', '7 / 260', 'clouds both ways (3 sprites each), stars at night');
    Row('SDL version', M.GLVendor, 'SDL3.dll next to the program');
    Row('SDL render backend', M.GLRenderer, Format('%d render drivers available', [M.GLExtCount]));
    Row('Presentation', 'streaming texture', M.GLVersion);
    Row('Texture', Format('%d x %d BGRA', [M.TexW, M.TexH]),
      'ARGB8888 streaming, nearest, SDL_UpdateTexture per band');
    Row('VSync', IfThen(M.VSync, 'on', 'off'), Format('SDL_SetRenderVSync, SDL_GetRenderVSync = %d', [M.SwapIntervalNow]));
    Row('Display refresh', FormatFloat('0', M.RefreshHz) + ' Hz', 'GetDeviceCaps(VREFRESH)');
    Row('Last pool error', IfThen(R.Pool.LastError = '', '-', R.Pool.LastError), '');
    Row('Last saved PNG', IfThen(M.LastSaved = '', '-', ExtractFileName(M.LastSaved)),
      ExtractFilePath(M.LastSaved));
    Row('Compiler', 'FPC ' + {$I %FPCVERSION%}, {$I %FPCTARGETOS%} + ' / ' + {$I %FPCTARGETCPU%});
    Row('Built', {$I %DATE%} + ' ' + {$I %TIME%}, '');
  end;
end;

{ ---------- time of day ---------- }

procedure TInfoForm.TimeModeClick(Sender: TObject);
begin
  View.SelectMode(TButton(Sender).Tag);
  RefreshTime;
end;

procedure TInfoForm.SeasonClick(Sender: TObject);
begin
  View.SelectSeason(TButton(Sender).Tag);
  RefreshTime;
end;

procedure TInfoForm.TimeSpinChange(Sender: TObject);
begin
  if FUpdating then Exit;
  View.Scene.AutoSeconds := FAutoSpin.Value;
  View.Scene.FadeSeconds := FFadeSpin.Value / 10;
end;

procedure TInfoForm.RefreshTime;
var
  Sc: TCityScene;
  K, M: Integer;

  procedure Row(const AName, AValue, ADetail: string);
  var
    It: TListItem;
  begin
    if K < FTimeList.Items.Count then
      It := FTimeList.Items[K]
    else
    begin
      It := FTimeList.Items.Add;
      It.SubItems.Add('');
      It.SubItems.Add('');
    end;
    if It.Caption <> AName then It.Caption := AName;
    if It.SubItems[0] <> AValue then It.SubItems[0] := AValue;
    if It.SubItems[1] <> ADetail then It.SubItems[1] := ADetail;
    Inc(K);
  end;

  function Bar(V: Single): string;
  begin
    Result := StringOfChar('#', Round(V * 20)) + StringOfChar('.', 20 - Round(V * 20));
  end;

begin
  Sc := View.Scene;
  K := 0;
  Row('Season', SeasonNames[Sc.Season], IfThen(Sc.Season = 0,
    'deep blue sky, lush trees, fireworks at night', IfThen(Sc.Season = 1,
    'overcast, wet street with puddles, rain, ripples, lightning, mirrored lights',
    'snow on roofs and sidewalks, bare trees, string lights, ice floes, snowfall')));
  Row('Now', ModeNames[Sc.CurrentMode], IfThen(Sc.ModeFrom <> Sc.ModeTo, 'fading ' +
    ModeNames[Sc.ModeFrom] + ' -> ' + ModeNames[Sc.ModeTo], 'steady'));
  Row('Blend', FormatFloat('0.00', Sc.Blend), Bar(Sc.Blend));
  Row('Night amount', FormatFloat('0.00', Sc.Night), Bar(Sc.Night) +
    '  window / bridge / street lights, beams, beacons');
  Row('Shade amount', FormatFloat('0.00', Sc.Shade), Bar(Sc.Shade) + '  brightness of moving bodies');
  Row('Auto cycle', IfThen(Sc.AutoCycle, 'on', 'off'), Format('%s s each, fade %s s',
    [FormatFloat('0', Sc.AutoSeconds), FormatFloat('0.0', Sc.FadeSeconds)]));
  Row('Traffic signal', IntToStr(Trunc(Frac(Sc.Time / 16) * 16)) + ' s of 16',
    'green 0-7 s, yellow 7-9 s, red 9-16 s');
  for M := 0 to ModeCount - 1 do
    Row('Palette ' + ModeNames[M], Format('lights %s, shade %s', [FormatFloat('0.00', ModeNight[M]),
      FormatFloat('0.00', ModeShade[M])]), IfThen(M = 0, 'warm low sun left, pink clouds, peach haze',
      IfThen(M = 1, 'high sun right, white clouds, blue water',
      'moon, stars, horizon glow, every light on')));
  FUpdating := True;
  try
    if not FAutoSpin.Focused then FAutoSpin.Value := Round(Sc.AutoSeconds);
    if not FFadeSpin.Focused then FFadeSpin.Value := Round(Sc.FadeSeconds * 10);
  finally
    FUpdating := False;
  end;
end;

{ ---------- overview ---------- }

function TInfoForm.OverviewText: string;
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Add('NEW YORK TOWN PAPERCUT - SDL3 + BGRABitmap on all cores, vsync');
    SL.Add('==============================================================');
    SL.Add('The New York skyline as layered cut paper: flat paper colours, a fine');
    SL.Add('paper grain, and a soft shadow under every paper sheet - the static');
    SL.Add('sheets have it baked in, everything that moves casts it live.');
    SL.Add('');
    SL.Add('Animated New York skyline by the river: two rows of towers, Empire State,');
    SL.Add('Chrysler, One WTC, a working crane, the Statue of Liberty, a suspension');
    SL.Add('bridge with traffic and a subway train, boats, a street with lamps, a');
    SL.Add('traffic signal and cars that stop at red, a plane and birds.');
    SL.Add('Three times of day to choose: MORNING, DAY, NIGHT (or AUTO cycling).');
    SL.Add('At night: lit windows (some switching on and off), lit landmarks and roof');
    SL.Add('beacons, the crane floodlight, the torch, bridge cable bulbs and lamps,');
    SL.Add('street lamps with light pools, head / tail lights and beams of every');
    SL.Add('vehicle, lit bus / train / ferry windows, plane navigation lights and');
    SL.Add('their reflections shimmering in the river.');
    SL.Add('Every pixel is drawn by BGRABitmap on the CPU, on all cores at once; SDL3');
    SL.Add('only shows the result, in step with the display (vsync, 60 Hz).');
    SL.Add('');
    SL.Add('FILES');
    SL.Add('  NewYorkTownPapercut.lpi      project (BGRABitmapPack, SDL3_package, LCL; -O3)');
    SL.Add('  NewYorkTownPapercut.lpr      program; --bench / --cpubench / --export modes');
    SL.Add('  ucityscene.pas       scene state + static resources for 3 palettes');
    SL.Add('                       (TCityScene), band renderer (TPainter, one per worker)');
    SL.Add('  urenderpool.pas      worker thread pool with per-job timing');
    SL.Add('  uframerenderer.pas   cuts the frame in bands and renders them on the pool');
    SL.Add('  usdlview.pas         SDL3 window and the vsync''ed render loop');
    SL.Add('  uexportjob.pas       PNG / SVG / GIF / MP4 export');
    SL.Add('  usvgrecorder.pas     SVG writer for the vector export');
    SL.Add('  umfvideo.pas         H.264 MP4 writer (Windows Media Foundation)');
    SL.Add('  uinfoform.pas        this window');
    SL.Add('');
    SL.Add('BUILD AND RUN');
    SL.Add('  IDE:  open NewYorkTownPapercut.lpi, press F9 (SDL3.dll next to the exe)');
    SL.Add('  CLI:  C:\lazarus\lazbuild.exe NewYorkTownPapercut.lpi');
    SL.Add('  NewYorkTownPapercut.exe --mode=morning|day|night|auto   start time of day');
    SL.Add('  NewYorkTownPapercut.exe --season=summer|rainy|winter    start season');
    SL.Add('  NewYorkTownPapercut.exe --bench=SECONDS   frame pacing in the real window,');
    SL.Add('        writes NewYorkTownPapercut-bench.txt (fps, intervals, missed vblanks), quits');
    SL.Add('  NewYorkTownPapercut.exe --novsync          start with vsync off (top speed)');
    SL.Add('  NewYorkTownPapercut.exe --cpubench out.png [width height [mode 0/1/2]]');
    SL.Add('        no window: times 60 frames with 1, 2, 4, 6, 8 and all threads,');
    SL.Add('        writes out.txt and saves the last frame');
    SL.Add('  NewYorkTownPapercut.exe --export folder [w h frames fps]');
    SL.Add('        no window: main + every layer, each for morning, day and night');
    SL.Add('');
    SL.Add('PAPERCUT');
    SL.Add('  - static parts are cut from sheets; each sheet is drawn on the work layer');
    SL.Add('    and stacked on the part with CompositeLayer (shadow = alpha sampled on a');
    SL.Add('    4 px grid, box blurred twice, offset (3, 6) x depth, 90/255 dark):');
    SL.Add('      sky: 7 wavy bands (0.3), 3 sun / moon rings (0.22), the disc (0.4)');
    SL.Add('      far city: 2 rows (0.25, 0.33)');
    SL.Add('      Manhattan: back row (0.45), landmarks (0.6), front row (0.75)');
    SL.Add('      Liberty (0.6); bridge: cables (0.25), towers + deck (0.8)');
    SL.Add('      street: road, far side with lamps / trees / signal (0.7), near walk (0.5)');
    SL.Add('      clouds: shaded back sheet (0.35) + lit front sheet (0.5)');
    SL.Add('  - grain: a fixed per-pixel hash at two scales, +-7 levels, on every sheet');
    SL.Add('  - live paper layers (crane load, bridge traffic + train, boats, cars, plane,');
    SL.Add('    birds): drawn on the band work layer (only the rows they can touch are');
    SL.Add('    cleared and sampled), composited with the shadow of LayerDepth[layer];');
    SL.Add('    then the same objects draw their lights on top (FPart 0 paper, 1 light)');
    SL.Add('  - river: 4 paper wave strips rolling in opposite directions, each with a');
    SL.Add('    thin edge shadow and a light crest; filled column by column (EdgeFill),');
    SL.Add('    far cheaper than antialiased polygons with hundreds of vertices');
    SL.Add('');
    SL.Add('NIGHT LIGHTS');
    SL.Add('  - every light ADDS light on opaque paper ((1 - d^2)^2 falloff), so it');
    SL.Add('    brightens what it falls on instead of veiling it');
    SL.Add('  - windows: lit cells (warm / white / cool, some blinds half down, some TV');
    SL.Add('    blue flicker) + a bloom (blurred copy under the sharp windows)');
    SL.Add('  - street lamps: bright head, light cone, pools on the sidewalk and road');
    SL.Add('  - cars: headlight beam + pool on the asphalt, lamp core; tail lights with a');
    SL.Add('    red glow on the road; BRAKE LIGHTS flare whenever a car slows or stands');
    SL.Add('    (by day too); taxi signs and bus windows glow');
    SL.Add('  - train: lit coaches spill light, front lamp beam, red tail light');
    SL.Add('  - boats: cabin, navigation and mast lights, each with a shimmering streak');
    SL.Add('    on the water; plane: nav lights, landing light, strobe, belly beacon');
    SL.Add('');
    SL.Add('SEASONS (tab 7, or 1 / 2 / 3 in the main window)');
    SL.Add('  SUMMER  deep blue sky, lush green trees, bright water; at night fireworks');
    SL.Add('          over the river: rockets rising, bursts falling with gravity, a');
    SL.Add('          flash and its colour on the water');
    SL.Add('  RAINY   grey palettes, two sheets of scalloped overcast, no sun disc;');
    SL.Add('          dark wet road with puddles; 450 slanted rain streaks, ripples on');
    SL.Add('          the river, splashes on the road; lightning every 5-11 s (bolt +');
    SL.Add('          double flash); every car lamp and street lamp mirrored in the wet');
    SL.Add('          road; the night sky glows orange from the city lights');
    SL.Add('  WINTER  pale cold sky, snow caps on every roof / setback / tower / deck,');
    SL.Add('          snowy sidewalks and Liberty island, slush along the curbs, bare');
    SL.Add('          trees with snow and coloured string lights at night, ice floes');
    SL.Add('          riding the waves, 420 flakes in three sizes swaying down');
    SL.Add('  - a season changes the palettes (SeasonTint) and re-cuts all sheets in');
    SL.Add('    Prepare, where the workers are idle; the picture from before is kept');
    SL.Add('    as a snapshot and fades out over 1.4 s (instant while paused)');
    SL.Add('  - rain, snow and sparks are hash functions of index and time: no state,');
    SL.Add('    exports replay them exactly; files get the season in their name');
    SL.Add('');
    SL.Add('TIME OF DAY (tab 7, or M / D / N / A in the main window)');
    SL.Add('  - every static part (sky, far city, Manhattan, river + Liberty, bridge,');
    SL.Add('    street) is cut once per window size for EACH palette: 3 sets');
    SL.Add('  - a change fades: the "from" set is copied, the "to" set is blended on');
    SL.Add('    top with alpha = blend (default 2.2 s); while paused it switches at once');
    SL.Add('  - the night amount (morning 0.32, day 0, night 1, blended) fades the light');
    SL.Add('    sprites in (window lights, bridge bulbs, street lamp pools) and drives');
    SL.Add('    every dynamic light: beacons, floodlights, head / tail lights, beams,');
    SL.Add('    lit windows of buses, the train and boats, reflections, stars');
    SL.Add('  - the shade amount (morning 0.86, day 1, night 0.42) darkens the moving');
    SL.Add('    bodies (cars, boats, train, plane) to match the palette');
    SL.Add('  - auto: morning -> day -> night -> morning, 14 s each');
    SL.Add('');
    SL.Add('EXPORT (tab 8, or E in the main window; --export on the command line)');
    SL.Add('  targets: the main picture and every single layer;');
    SL.Add('  time of day: the live view and / or morning, day, night (file suffix)');
    SL.Add('  PNG first frame (+ optional PNG sequence), SVG vector, animated GIF, H.264 MP4');
    SL.Add('  - SVG: the painters run in vector mode: every polygon, ellipse, line and');
    SL.Add('    gradient is written as an SVG element in frame pixels; light sprites are');
    SL.Add('    groups with opacity = night amount, cloud softness is feGaussianBlur');
    SL.Add('  - own scene + own frame renderer on all physical cores, at any size');
    SL.Add('  - the export scene copies the window''s animation state; every target');
    SL.Add('    replays the same frames with the same random seed, so the files line');
    SL.Add('    up frame for frame and the layers can be stacked again in an editor');
    SL.Add('  - layers: transparent background (PNG / GIF alpha); MP4 has no alpha,');
    SL.Add('    so layer videos are flattened on white');
    SL.Add('  - MP4 through Windows Media Foundation (GPU encoder, software fallback),');
    SL.Add('    width and height rounded down to even numbers');
    SL.Add('  - the live window pauses while exporting');
    SL.Add('');
    SL.Add('HOTKEYS');
    SL.Add('  1      summer   2  rainy     3    winter');
    SL.Add('  M      morning               D    day');
    SL.Add('  N      night                 A    auto cycle on / off');
    SL.Add('  Space  pause / resume        V    vsync on / off');
    SL.Add('  F11    full screen           S    save frame as PNG');
    SL.Add('  H      hide / show caption   I, F1  this window (opens by itself at startup)');
    SL.Add('  E      export tab');
    SL.Add('  Esc    leave full screen      close the SDL window to quit');
    SL.Add('  in this window: 1..8 switch tabs, Esc closes it');
    SL.Add('');
    SL.Add('RENDER LOOP (LCL idle handler, main thread; SDL and LCL share it)');
    SL.Add('  1. Wait     collect the bands the workers rendered during the last vsync');
    SL.Add('  2. Resize   window size changed -> re-cut the static parts (3 palettes)');
    SL.Add('  3. Upload   SDL_UpdateTexture, one call per band, straight from the bitmaps');
    SL.Add('              (rows are bottom-up on Windows: drawn with SDL_FLIP_VERTICAL)');
    SL.Add('  4. Update   advance the animation (traffic, signal, fade), start the next');
    SL.Add('              frame on all cores (returns at once)');
    SL.Add('  5. Present  SDL_RenderTexture + SDL_RenderPresent; with vsync this blocks until');
    SL.Add('              the display refresh while the workers keep rendering');
    SL.Add('  The picture on screen is one frame behind the simulation; in exchange the');
    SL.Add('  whole render time hides behind the vsync wait.');
    SL.Add('');
    SL.Add('MULTI-CORE BANDS');
    SL.Add('  - the frame is cut in (threads x bands per thread) horizontal bands;');
    SL.Add('    workers take the next free band (interlocked counter)');
    SL.Add('  - one worker per PHYSICAL core by default (GetLogicalProcessorInformation):');
    SL.Add('    a second hyper-thread on the same core made frames slower, not faster');
    SL.Add('  - adaptive bands: every 20 frames the band borders move half way towards');
    SL.Add('    an equal share of the measured cost (road and river rows cost more)');
    SL.Add('  - each part checks the rows it touches (RowsHit) per object: a car, a');
    SL.Add('    glow, a boat is only drawn by the bands it reaches');
    SL.Add('  - shared bitmaps are drawn with BlendBitmap (own code, read-only, with an');
    SL.Add('    opacity for fades and lights): TBGRABitmap.PutImage keeps scan state in');
    SL.Add('    the SOURCE bitmap, so threads drawing the same sprite corrupt each other');
    SL.Add('  - reflections and boat light streaks are thousands of tiny strokes: HDash');
    SL.Add('    writes their pixel spans directly instead of antialiased lines');
    SL.Add('  - text is drawn only on the main thread (caption, at resize)');
    SL.Add('');
    SL.Add('MEASURED (--cpubench, night, 6 physical / 12 logical cores)');
    SL.Add('  1024 x 576    1 thread 17.0 ms   6 threads 4.2 ms  (about 235 fps)');
    SL.Add('');
    SL.Add('ADDING A LAYER');
    SL.Add('  1. add an id to TLayerId and its LayerNames / LayerKinds / LayerDepth /');
    SL.Add('     LayerNotes entries');
    SL.Add('  2. static: cut it per palette in TCityScene.RenderStatic (Crop + TakeSvg)');
    SL.Add('     and draw it with Pair(...); dynamic: write TPainter.DrawXxx in design');
    SL.Add('     coordinates (P(), S(), Box, Glow, HDash), lights scaled by Scene.Night');
    SL.Add('  3. in TPainter.RenderBand: if LayerOn[id] then DrawXxx; Mark(id)');
    SL.Add('');
    SL.Add('CURRENT PARAMETERS');
    SL.Add('==================');
    SL.Add(View.Scene.DescribeParams);
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

procedure TInfoForm.RefreshOverview;
var
  P: TPoint;
begin
  P := FOverview.CaretPos;
  FOverview.Lines.Text := OverviewText;
  FOverview.CaretPos := P;
end;

function TInfoForm.ReportText: string;
var
  Id: TLayerId;
  SL: TStringList;
  I: Integer;
  R: TFrameRenderer;
begin
  R := View.Renderer;
  SL := TStringList.Create;
  try
    SL.Text := OverviewText;
    SL.Add('LIVE PERFORMANCE');
    SL.Add(Format('  fps %s, refresh %s Hz, vsync %s, missed %d',
      [FormatFloat('0.0', View.Fps), FormatFloat('0', View.RefreshHz),
      IfThen(View.VSync, 'on', 'off'), View.MissedFrames]));
    SL.Add(Format('  render wall %s, cpu %s (%d threads, %d bands)', [Ms(R.WallSmooth),
      Ms(R.CpuSmooth), R.Threads, R.BandCount]));
    SL.Add(Format('  upload %s, swap %s, wait %s', [Ms(View.LastUploadMs),
      Ms(View.LastSwapMs), Ms(View.LastWaitMs)]));
    for Id := Low(TLayerId) to High(TLayerId) do
      SL.Add(Format('  %-14s %9s cpu  %s', [LayerNames[Id], Ms(R.LayerCpuMs[Id]),
        IfThen(View.Scene.LayerOn[Id], 'on', 'OFF')]));
    SL.Add('');
    SL.Add('WORKERS (last frame)');
    for I := 0 to R.Threads - 1 do
      SL.Add(Format('  worker %2d  %9s  %d bands', [I, Ms(R.WorkerMs[I]), R.WorkerJobs[I]]));
    SL.Add('');
    SL.Add('OBJECTS');
    RefreshObjects;
    for I := 0 to FObjList.Items.Count - 1 do
      with FObjList.Items[I] do
        SL.Add(Format('  %-20s %-26s %s', [Caption, SubItems[0], SubItems[1]]));
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

{ ---------- performance ---------- }

{ The live panels are drawn with plain GDI on a back buffer: the info window
  runs on the same thread as the render loop, so its paint must stay well
  under a millisecond or it would cost vsync frames. }

function TInfoForm.Buffer(ABox: TPaintBox): TCanvas;
begin
  if FBuf = nil then FBuf := TBitmap.Create;
  if (FBuf.Width <> ABox.Width) or (FBuf.Height <> ABox.Height) then
    FBuf.SetSize(Max(1, ABox.Width), Max(1, ABox.Height));
  Result := FBuf.Canvas;
  Result.Brush.Color := RGBToColor(250, 250, 248);
  Result.FillRect(0, 0, FBuf.Width, FBuf.Height);
  Result.Font.Name := 'Segoe UI';
  Result.Font.Height := -Scale96ToForm(14);
  Result.Font.Color := RGBToColor(40, 40, 40);
  Result.Brush.Style := bsClear;
end;

procedure TInfoForm.PerfPaint(Sender: TObject);
const
  Pad = 12;
var
  C: TCanvas;
  M: TSDLView;
  R: TFrameRenderer;
  W, H, Y, I, K, GX, GY, GW, GH, LH, N, X: Integer;
  MaxV, V, Period, SumI, MaxI, SumR, MaxR: Double;
  Pts: array[0..HistLen - 1] of TPoint;

  procedure Line(const S: string; Bold: Boolean = False);
  begin
    if Bold then C.Font.Style := [fsBold] else C.Font.Style := [];
    C.TextOut(Pad, Y, S);
    Inc(Y, LH);
  end;

  procedure Plot(const A: array of Single; Color: TColor);
  var
    J, Idx: Integer;
  begin
    for J := 0 to HistLen - 1 do
    begin
      Idx := (M.HistPos + J) mod HistLen;  // oldest first
      Pts[J] := Point(GX + Round(J / (HistLen - 1) * GW),
        GY + GH - Round(Min(A[Idx], MaxV) / MaxV * GH));
    end;
    C.Pen.Color := Color;
    C.Pen.Width := 2;
    C.Polyline(Pts);
  end;

  procedure Legend(const S: string; Color: TColor);
  begin
    C.Brush.Style := bsSolid;
    C.Brush.Color := Color;
    C.FillRect(X, Y + 5, X + 14, Y + LH - 6);
    C.Brush.Style := bsClear;
    C.TextOut(X + 18, Y, S);
    X := X + 26 + C.TextWidth(S);
  end;

begin
  M := View;
  R := M.Renderer;
  W := FPerfBox.Width;
  H := FPerfBox.Height;
  if (W < 10) or (H < 10) then Exit;
  C := Buffer(FPerfBox);
  LH := Scale96ToForm(19);
  Period := 1000 / Max(1, M.RefreshHz);

  SumI := 0; MaxI := 0; SumR := 0; MaxR := 0; N := 0;
  for I := 0 to HistLen - 1 do
    if M.IntervalHist[I] > 0 then
    begin
      SumI := SumI + M.IntervalHist[I];
      MaxI := Max(MaxI, M.IntervalHist[I]);
      SumR := SumR + M.RenderHist[I];
      MaxR := Max(MaxR, M.RenderHist[I]);
      Inc(N);
    end;
  Y := Pad;
  Line('LIVE PERFORMANCE', True);
  Line(Format('FPS %s   display %s Hz (%s per frame)   vsync %s   missed frames %d',
    [FormatFloat('0.0', M.Fps), FormatFloat('0', M.RefreshHz), Ms(Period),
    IfThen(M.VSync, 'ON', 'off'), M.MissedFrames]));
  if N > 0 then
    Line(Format('Present interval avg %s  max %s     Render (all cores) avg %s  max %s',
      [Ms(SumI / N), Ms(MaxI), Ms(SumR / N), Ms(MaxR)]));
  Line(Format('Render wall %s   CPU %s   speed-up %sx on %d threads   headroom %s',
    [Ms(R.WallSmooth), Ms(R.CpuSmooth), FormatFloat('0.0', R.CpuSmooth / Max(0.01, R.WallSmooth)),
    R.Threads, Ms(Period - R.WallSmooth)]));
  Line(Format('Main thread: wait %s   upload %s   update+sort %s   draw+swap %s   info paint %s',
    [Ms(M.LastWaitMs), Ms(M.LastUploadMs), Ms(M.LastUpdateMs), Ms(M.LastSwapMs), Ms(FPaintMs)]));
  Line(Format('Frame %d x %d in %d bands (%s)   theoretical max %s fps',
    [R.Width, R.Height, R.BandCount, IfThen(R.Adaptive, 'adaptive', 'equal'),
    FormatFloat('0', 1000 / Max(0.01, R.WallSmooth))]));
  Inc(Y, LH div 2);

  Line('Frame history (last ' + IntToStr(HistLen) + ' presents, ms)', True);
  X := Pad;
  C.Font.Style := [];
  Legend('present interval', RGBToColor(40, 110, 210));
  Legend('render wall', RGBToColor(240, 120, 30));
  Legend('main waits for workers', RGBToColor(210, 40, 40));
  Legend('upload', RGBToColor(40, 160, 80));
  Inc(Y, LH);
  GX := Pad + Scale96ToForm(36);
  GY := Y;
  GW := W - GX - Pad;
  GH := Max(80, H - Y - Pad);
  C.Brush.Style := bsSolid;
  C.Brush.Color := clWhite;
  C.Pen.Color := RGBToColor(200, 200, 200);
  C.Pen.Width := 1;
  C.Rectangle(GX, GY, GX + GW, GY + GH);
  C.Brush.Style := bsClear;
  MaxV := Max(Period * 2.2, 10);
  for I := 0 to HistLen - 1 do
    MaxV := Max(MaxV, Min(M.IntervalHist[I], 200) * 1.1);
  C.Font.Height := -Scale96ToForm(11);
  C.Font.Color := RGBToColor(110, 110, 110);
  for K := 0 to 3 do
  begin
    case K of
      0: V := 0;
      1: V := Period;
      2: V := Period * 2;
    else
      V := MaxV;
    end;
    if (K = 3) or (V < MaxV) then
    begin
      I := GY + GH - Round(V / MaxV * GH);
      C.Pen.Color := RGBToColor(200, 200, 200);
      C.Line(GX, I, GX + GW, I);
      C.TextOut(Pad, I - Scale96ToForm(7), FormatFloat('0.0', V));
    end;
  end;
  Plot(M.UploadHist, RGBToColor(40, 160, 80));
  Plot(M.WaitHist, RGBToColor(210, 40, 40));
  Plot(M.RenderHist, RGBToColor(240, 120, 30));
  Plot(M.IntervalHist, RGBToColor(40, 110, 210));
  FPerfBox.Canvas.Draw(0, 0, FBuf);
end;

{ ---------- threads ---------- }

procedure TInfoForm.ThreadPaint(Sender: TObject);
const
  Pad = 12;
var
  C: TCanvas;
  R: TFrameRenderer;
  W, H, Y, I, LH, BarX, BarW, BH: Integer;
  MaxV, Util: Double;

  procedure Line(const S: string; Bold: Boolean = False);
  begin
    if Bold then C.Font.Style := [fsBold] else C.Font.Style := [];
    C.TextOut(Pad, Y, S);
    Inc(Y, LH);
  end;

  procedure Bar(V: Double; Color: TColor);
  begin
    C.Brush.Style := bsSolid;
    C.Brush.Color := Color;
    C.FillRect(BarX, Y + 2, BarX + Max(1, Round(V / MaxV * BarW)), Y + BH - 2);
    C.Brush.Style := bsClear;
  end;

begin
  R := View.Renderer;
  W := FThreadBox.Width;
  H := FThreadBox.Height;
  if (W < 10) or (H < 10) then Exit;
  C := Buffer(FThreadBox);
  LH := Scale96ToForm(19);
  Util := R.CpuSmooth / Max(0.01, R.WallSmooth * R.Threads) * 100;
  Y := Pad;
  Line('WORK SPLIT (last frame)', True);
  Line(Format('%d workers (%d physical / %d logical cores), %d bands, wall %s, CPU %s, utilisation %s %%',
    [R.Threads, PhysicalCores, TThread.ProcessorCount, R.BandCount, Ms(R.RenderWallMs),
    Ms(R.RenderCpuMs), FormatFloat('0', Util)]));
  Line(Format('Adaptive bands %s: every %d frames the borders move so every band costs about', [
    IfThen(R.Adaptive, 'ON', 'off'), BalanceEvery]));
  Line(Format('the same (%d rebalances so far). Colour = worker.', [R.Rebalances]));
  Inc(Y, LH div 2);

  Line('Workers', True);
  BarX := Pad + Scale96ToForm(80);
  BarW := W - BarX - Pad - Scale96ToForm(140);
  MaxV := 0.1;
  for I := 0 to R.Threads - 1 do
    MaxV := Max(MaxV, R.WorkerMs[I]);
  BH := Max(8, Min(LH, (H div 2 - Y) div Max(1, R.Threads)));
  for I := 0 to R.Threads - 1 do
  begin
    C.Font.Style := [];
    C.TextOut(Pad, Y, 'worker ' + IntToStr(I));
    Bar(R.WorkerMs[I], WorkerColor(I));
    C.TextOut(BarX + Round(R.WorkerMs[I] / MaxV * BarW) + 6, Y,
      Format('%s  (%d bands)', [Ms(R.WorkerMs[I]), R.WorkerJobs[I]]));
    Inc(Y, BH);
  end;
  Inc(Y, LH div 2);

  Line('Bands (top of the frame first): rows, cost, worker', True);
  MaxV := 0.1;
  for I := 0 to R.BandCount - 1 do
    MaxV := Max(MaxV, R.BandMs[I]);
  BH := Max(4, Min(LH, (H - Y - Pad) div Max(1, R.BandCount)));
  for I := 0 to R.BandCount - 1 do
  begin
    if Y + BH > H then Break;
    C.Font.Style := [];
    if BH >= 12 then
      C.TextOut(Pad, Y, Format('%d+%d', [R.BandTops[I], R.Bands[I].Height]));
    Bar(R.BandMs[I], WorkerColor(R.BandWorker[I]));
    if BH >= 12 then
      C.TextOut(BarX + Round(R.BandMs[I] / MaxV * BarW) + 6, Y,
        Format('%s  w%d', [Ms(R.BandMs[I]), R.BandWorker[I]]));
    Inc(Y, BH);
  end;
  FThreadBox.Canvas.Draw(0, 0, FBuf);
end;

procedure TInfoForm.AdaptiveClick(Sender: TObject);
begin
  if FUpdating then Exit;
  View.SetAdaptive(FAdaptiveCheck.Checked);
end;

procedure TInfoForm.ThreadsChange(Sender: TObject);
begin
  if FUpdating then Exit;
  View.SetThreads(FThreadSpin.Value);
end;

procedure TInfoForm.BandsChange(Sender: TObject);
begin
  if FUpdating then Exit;
  View.SetBandsPerThread(FBandSpin.Value);
end;

procedure TInfoForm.VSyncClick(Sender: TObject);
begin
  if FUpdating then Exit;
  View.VSync := FVSyncCheck.Checked;
  View.ResetStats;
end;

procedure TInfoForm.ResetClick(Sender: TObject);
begin
  View.ResetStats;
end;

{ ---------- palette ---------- }

procedure TInfoForm.PalettePaint(Sender: TObject);
var
  B: TBGRABitmap;
  I, Cols, CW, RH, X, Y, Sw: Integer;
  C: TBGRAPixel;
begin
  if (FPaletteBox.Width < 10) or (FPaletteBox.Height < 10) then Exit;
  B := TBGRABitmap.Create(FPaletteBox.Width, FPaletteBox.Height, BGRA(250, 250, 248));
  try
    B.FontName := 'Segoe UI';
    B.FontQuality := fqFineAntialiasing;
    B.FontHeight := Scale96ToForm(14);
    Cols := Max(1, FPaletteBox.Width div Scale96ToForm(240));
    CW := FPaletteBox.Width div Cols;
    RH := Scale96ToForm(44);
    Sw := Scale96ToForm(34);
    for I := 0 to High(PaletteNames) do
    begin
      X := (I mod Cols) * CW + Scale96ToForm(12);
      Y := (I div Cols) * RH + Scale96ToForm(12);
      C := StrToBGRA(PaletteHex[I]);
      B.FillRoundRectAntialias(X + 2, Y + 4, X + Sw + 2, Y + Sw + 4, 5, 5, BGRA(0, 0, 0, 40));
      B.FillRoundRectAntialias(X, Y, X + Sw, Y + Sw, 5, 5, C);
      B.RoundRectAntialias(X, Y, X + Sw, Y + Sw, 5, 5, BGRA(30, 30, 30), 1);
      B.FontStyle := [fsBold];
      B.TextOut(X + Sw + 10, Y, PaletteNames[I], BGRA(40, 40, 40));
      B.FontStyle := [];
      B.TextOut(X + Sw + 10, Y + Scale96ToForm(17),
        Format('%s   rgb %d, %d, %d', [PaletteHex[I], C.red, C.green, C.blue]), BGRA(100, 100, 100));
    end;
    B.Draw(FPaletteBox.Canvas, 0, 0, True);
  finally
    B.Free;
  end;
end;

{ ---------- live refresh ---------- }

procedure TInfoForm.RefreshControls;
begin
  FUpdating := True;
  try
    if View.Paused then FBtnPause.Caption := 'Resume' else FBtnPause.Caption := 'Pause';
    if View.Scene.ShowCaption then FBtnCaption.Caption := 'Hide caption'
    else FBtnCaption.Caption := 'Show caption';
    if FVSyncCheck.Checked <> View.VSync then FVSyncCheck.Checked := View.VSync;
    if not FThreadSpin.Focused then FThreadSpin.Value := View.Renderer.Threads;
    if not FBandSpin.Focused then FBandSpin.Value := View.Renderer.BandsPerThread;
    if FAdaptiveCheck.Checked <> View.Renderer.Adaptive then
      FAdaptiveCheck.Checked := View.Renderer.Adaptive;
    FStatus.Caption := Format('%s fps   vsync %s   render %s on %d threads',
      [FormatFloat('0.0', View.Fps), IfThen(View.VSync, 'on', 'off'),
      Ms(View.Renderer.WallSmooth), View.Renderer.Threads]);
  finally
    FUpdating := False;
  end;
end;

procedure TInfoForm.TimerTick(Sender: TObject);
var
  T0: Double;
begin
  if not Visible then Exit;
  RefreshControls;
  T0 := HiResMs;
  case FPages.ActivePageIndex of
    1: FPerfBox.Repaint;
    2: FThreadBox.Repaint;
    3: RefreshLayers;
    4: RefreshObjects;
    6: RefreshTime;
  end;
  FPaintMs := HiResMs - T0;
end;

procedure TInfoForm.PageChange(Sender: TObject);
begin
  case FPages.ActivePageIndex of
    0: RefreshOverview;
    3: RefreshLayers;
    4: RefreshObjects;
    6: RefreshTime;
    7: ExpEstimate(nil);
  end;
end;

{ ---------- buttons ---------- }

procedure TInfoForm.PauseClick(Sender: TObject);
begin
  View.Paused := not View.Paused;
  RefreshControls;
end;

procedure TInfoForm.CaptionClick(Sender: TObject);
begin
  View.ToggleCaption;
  RefreshControls;
end;

procedure TInfoForm.SaveClick(Sender: TObject);
begin
  View.RequestSave;
  FStatus.Caption := 'saving on the next frame...';
end;

procedure TInfoForm.CopyClick(Sender: TObject);
begin
  Clipboard.AsText := ReportText;
  FStatus.Caption := 'report copied to the clipboard';
end;

procedure TInfoForm.RefreshClick(Sender: TObject);
begin
  RefreshOverview;
end;

{ ---------- export ---------- }

function TInfoForm.AddSpin(AParent: TWinControl; AMin, AMax, AValue: Integer): TSpinEdit;
begin
  Result := TSpinEdit.Create(Self);
  Result.Parent := AParent;
  Result.Align := alLeft;
  Result.BorderSpacing.Around := 4;
  Result.MinValue := AMin;
  Result.MaxValue := AMax;
  Result.Value := AValue;
  Result.Width := Scale96ToForm(70);
  Inc(FOrder);
  Result.Left := FOrder * 1000;
  Result.OnChange := @ExpEstimate;
end;

function TInfoForm.AddCheck(AParent: TWinControl; const ACaption: string;
  AChecked: Boolean): TCheckBox;
begin
  Result := TCheckBox.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Checked := AChecked;
  Result.Align := alLeft;
  Result.BorderSpacing.Left := 8;
  Result.BorderSpacing.Right := 4;
  Inc(FOrder);
  Result.Left := FOrder * 1000;
  Result.OnClick := @ExpEstimate;
end;

procedure TInfoForm.BuildExportTab(Tab: TTabSheet);
var
  Bar: TPanel;
  Id: TLayerId;
  Why: string;
begin
  { folder }
  Bar := AddBar(Tab);
  AddLabel(Bar, 'Folder');
  FExpFolder := TDirectoryEdit.Create(Self);
  FExpFolder.Parent := Bar;
  FExpFolder.Align := alClient;
  FExpFolder.BorderSpacing.Around := 4;
  FExpFolder.Text := ExtractFilePath(ParamStr(0)) + 'export';
  AddButton(Bar, 'Open', @ExpOpenFolder).Align := alRight;

  { size }
  Bar := AddBar(Tab);
  AddLabel(Bar, 'Size');
  FExpW := AddSpin(Bar, 16, 7680, 1024);
  AddLabel(Bar, 'x');
  FExpH := AddSpin(Bar, 16, 4320, 576);
  AddButton(Bar, 'Window size', @ExpWindowSize);
  AddButton(Bar, 'Half', @ExpHalfSize);

  { time }
  Bar := AddBar(Tab);
  AddLabel(Bar, 'Frames');
  FExpFrames := AddSpin(Bar, 1, 100000, 120);
  AddLabel(Bar, 'FPS');
  FExpFps := AddSpin(Bar, 1, 120, 30);
  AddLabel(Bar, 'MP4 kbps');
  FExpKbps := AddSpin(Bar, 500, 200000, 12000);
  FExpKbps.Width := Scale96ToForm(80);

  { formats }
  Bar := AddBar(Tab);
  AddLabel(Bar, 'Formats');
  FExpPng := AddCheck(Bar, 'PNG (first frame)', True);
  FExpSeq := AddCheck(Bar, 'PNG sequence', False);
  FExpSvg := AddCheck(Bar, 'SVG (vector)', True);
  FExpGif := AddCheck(Bar, 'GIF', True);
  FExpMp4 := AddCheck(Bar, 'MP4', True);
  FExpHw := AddCheck(Bar, 'GPU encoder', True);
  if not MP4Available(Why) then
  begin
    FExpMp4.Checked := False;
    FExpMp4.Enabled := False;
    FExpMp4.Hint := Why;
    FExpMp4.ShowHint := True;
  end;

  { time of day }
  Bar := AddBar(Tab);
  AddLabel(Bar, 'Time of day');
  FExpLive := AddCheck(Bar, 'As shown', True);
  FExpMorning := AddCheck(Bar, 'Morning', False);
  FExpDay := AddCheck(Bar, 'Day', False);
  FExpNight := AddCheck(Bar, 'Night', False);
  FExpLive.OnClick := @ExpEstimate;
  FExpMorning.OnClick := @ExpEstimate;
  FExpDay.OnClick := @ExpEstimate;
  FExpNight.OnClick := @ExpEstimate;

  { targets }
  Bar := AddBar(Tab);
  AddLabel(Bar, 'Targets');
  AddButton(Bar, 'Main only', @ExpMainOnly);
  AddButton(Bar, 'Main + all layers', @ExpAllTargets);
  AddButton(Bar, 'None', @ExpNoTargets);
  FExpTargets := TCheckListBox.Create(Self);
  FExpTargets.Parent := Tab;
  FExpTargets.Align := alTop;
  FExpTargets.Height := Scale96ToForm(170);
  Inc(FOrder);
  FExpTargets.Top := FOrder * 1000;
  FExpTargets.Columns := 2;
  FExpTargets.Items.Add(TargetName(TargetMain));
  for Id := Low(TLayerId) to High(TLayerId) do
    FExpTargets.Items.Add(TargetName(Ord(Id)));
  FExpTargets.Checked[0] := True;
  FExpTargets.OnClickCheck := @ExpEstimate;

  { run }
  Bar := AddBar(Tab);
  FExpRun := AddButton(Bar, 'Export', @ExpRunClick);
  FExpCancel := AddButton(Bar, 'Cancel', @ExpCancelClick);
  FExpCancel.Enabled := False;
  FExpInfo := AddLabel(Bar, '');
  FExpInfo.Align := alClient;
  FExpProgress := TProgressBar.Create(Self);
  FExpProgress.Parent := Tab;
  FExpProgress.Align := alTop;
  FExpProgress.Height := Scale96ToForm(18);
  FExpProgress.BorderSpacing.Around := 4;
  Inc(FOrder);
  FExpProgress.Top := FOrder * 1000;

  FExpLog := TMemo.Create(Self);
  FExpLog.Parent := Tab;
  FExpLog.Align := alClient;
  FExpLog.ReadOnly := True;
  FExpLog.ScrollBars := ssBoth;
  FExpLog.WordWrap := False;
  FExpLog.Font.Name := 'Consolas';
  FExpLog.Font.Size := 9;
  FExpLog.Lines.Add('Layers are exported alone on a transparent background');
  FExpLog.Lines.Add('(PNG / GIF keep the alpha; MP4 is flattened on white).');
  FExpLog.Lines.Add('Morning / Day / Night add _morning / _day / _night to the file names.');
  FExpLog.Lines.Add('All targets replay the same frames, so they stack frame for frame.');
  FExpLog.Lines.Add('The live window pauses while exporting.');
end;

{ files and a rough time estimate from the measured render speed }
procedure TInfoForm.ExpEstimate(Sender: TObject);
var
  I, N, Files: Integer;
  PerFrame: Double;
begin
  if FExpInfo = nil then Exit;
  N := 0;
  for I := 0 to FExpTargets.Count - 1 do
    if FExpTargets.Checked[I] then Inc(N);
  N := N * Max(1, Ord(FExpLive.Checked) + Ord(FExpMorning.Checked) + Ord(FExpDay.Checked) +
    Ord(FExpNight.Checked));
  Files := N * (Ord(FExpPng.Checked) + Ord(FExpSvg.Checked) + Ord(FExpGif.Checked) +
    Ord(FExpMp4.Checked and FExpMp4.Enabled))
    + Ord(FExpSeq.Checked) * N * FExpFrames.Value;
  // render time scales with the pixel count of the live frame
  PerFrame := View.Renderer.WallSmooth * (FExpW.Value * FExpH.Value) /
    Max(1, View.Renderer.Width * View.Renderer.Height) + 1;
  FExpInfo.Caption := Format('%d targets, %d files, %s s of animation, about %s s to render',
    [N, Files, FormatFloat('0.0', FExpFrames.Value / Max(1, FExpFps.Value)),
    FormatFloat('0', N * FExpFrames.Value * PerFrame / 1000)]);
end;

procedure TInfoForm.ExpWindowSize(Sender: TObject);
begin
  FExpW.Value := View.Renderer.Width;
  FExpH.Value := View.Renderer.Height;
end;

procedure TInfoForm.ExpHalfSize(Sender: TObject);
begin
  FExpW.Value := Max(16, FExpW.Value div 2);
  FExpH.Value := Max(16, FExpH.Value div 2);
end;

procedure TInfoForm.ExpAllTargets(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to FExpTargets.Count - 1 do
    FExpTargets.Checked[I] := True;
  ExpEstimate(nil);
end;

procedure TInfoForm.ExpNoTargets(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to FExpTargets.Count - 1 do
    FExpTargets.Checked[I] := False;
  ExpEstimate(nil);
end;

procedure TInfoForm.ExpMainOnly(Sender: TObject);
begin
  ExpNoTargets(nil);
  FExpTargets.Checked[0] := True;
  ExpEstimate(nil);
end;

procedure TInfoForm.ExpOpenFolder(Sender: TObject);
begin
  ForceDirectories(FExpFolder.Text);
  OpenDocument(FExpFolder.Text);
end;

procedure TInfoForm.ExpCancelClick(Sender: TObject);
begin
  FExpCancelled := True;
end;

procedure TInfoForm.ExpProgressCb(const AMessage: string; ADone, ATotal: Integer;
  var ACancel: Boolean);
begin
  FExpProgress.Max := Max(1, ATotal);
  FExpProgress.Position := ADone;
  FExpInfo.Caption := AMessage;
  if (Pos('rendering', AMessage) = 1) or (Pos('writing', AMessage) = 1) or
    (Pos('ERROR', AMessage) = 1) then
    FExpLog.Lines.Add(AMessage);
  Application.ProcessMessages;  // keeps the window alive; the live loop is paused
  ACancel := FExpCancelled;
end;

procedure TInfoForm.ExpRunClick(Sender: TObject);
var
  Opt: TExportOptions;
  Res: TExportResult;
  I: Integer;
begin
  if FExpBusy then Exit;
  Opt := DefaultExportOptions(FExpW.Value, FExpH.Value);
  Opt.Folder := FExpFolder.Text;
  Opt.Frames := FExpFrames.Value;
  Opt.Fps := FExpFps.Value;
  Opt.Png := FExpPng.Checked;
  Opt.PngSequence := FExpSeq.Checked;
  Opt.Svg := FExpSvg.Checked;
  Opt.Gif := FExpGif.Checked;
  Opt.Mp4 := FExpMp4.Checked and FExpMp4.Enabled;
  Opt.Mp4Kbps := FExpKbps.Value;
  Opt.Mp4Hardware := FExpHw.Checked;
  Opt.Targets := [];
  for I := 0 to FExpTargets.Count - 1 do
    if FExpTargets.Checked[I] then
      Opt.Targets := Concat(Opt.Targets, [I - 1]);  // item 0 = main = -1
  if Length(Opt.Targets) = 0 then
  begin
    FExpLog.Lines.Add('Nothing to export: tick at least one target.');
    Exit;
  end;
  Opt.Modes := [];
  if FExpLive.Checked then Opt.Modes := Concat(Opt.Modes, [ModeLive]);
  if FExpMorning.Checked then Opt.Modes := Concat(Opt.Modes, [0]);
  if FExpDay.Checked then Opt.Modes := Concat(Opt.Modes, [1]);
  if FExpNight.Checked then Opt.Modes := Concat(Opt.Modes, [2]);
  if Length(Opt.Modes) = 0 then
  begin
    FExpLog.Lines.Add('Nothing to export: tick at least one time of day.');
    Exit;
  end;
  if not (Opt.Png or Opt.PngSequence or Opt.Svg or Opt.Gif or Opt.Mp4) then
  begin
    FExpLog.Lines.Add('Nothing to export: tick at least one format.');
    Exit;
  end;

  FExpBusy := True;
  FExpCancelled := False;
  FExpRun.Enabled := False;
  FExpCancel.Enabled := True;
  View.Exporting := True;
  View.Renderer.Wait;
  FExpLog.Lines.Add('');
  FExpLog.Lines.Add(Format('== export %d x %d, %d frames at %d fps, %d targets -> %s',
    [Opt.Width, Opt.Height, Opt.Frames, Opt.Fps, Length(Opt.Targets), Opt.Folder]));
  try
    Res := RunExport(View.Scene, Opt, @ExpProgressCb);
    try
      FExpLog.Lines.AddStrings(Res.Files);
      FExpLog.Lines.Add(Format('== %s: %d frames rendered in %s s, %d errors',
        [IfThen(Res.Cancelled, 'cancelled', 'done'), Res.FramesRendered,
        FormatFloat('0.0', Res.Ms / 1000), Res.Errors.Count]));
      FExpLog.Lines.AddStrings(Res.Errors);
    finally
      Res.Files.Free;
      Res.Errors.Free;
    end;
  except
    on E: Exception do
      FExpLog.Lines.Add('== export failed: ' + E.Message);
  end;
  View.Exporting := False;
  View.Redraw;
  FExpBusy := False;
  FExpRun.Enabled := True;
  FExpCancel.Enabled := False;
  FExpInfo.Caption := '';
end;

procedure TInfoForm.ShowExportTab;
begin
  FPages.ActivePageIndex := TabCount - 1;
  if FExpW.Value = 450 then ExpWindowSize(nil);
  ExpEstimate(nil);
end;

{ This form is the LCL main form: closing it only hides it, the program ends
  when the SDL window is closed. }
procedure TInfoForm.InfoClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caHide;
end;

procedure TInfoForm.CloseClick(Sender: TObject);
begin
  Hide;
end;

procedure TInfoForm.FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    Hide;
    Key := 0;
  end
  else if (Key >= VK_1) and (Key < VK_1 + TabCount) and (Shift = []) and
    not (ActiveControl is TSpinEdit) then
  begin
    FPages.ActivePageIndex := Key - VK_1;
    PageChange(FPages);
    Key := 0;
  end;
end;

end.
