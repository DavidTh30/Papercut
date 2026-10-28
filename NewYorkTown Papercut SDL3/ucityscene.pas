unit uCityScene;

{ New York Town Papercut - the animated New York skyline as layered cut paper,
  at morning, day or night.

  Paper look: flat paper colours, a fine paper grain on every cut part and a soft
  shadow under every paper layer. Static parts are cut from several sheets (sky
  bands, sun rings, far city, back row, landmarks, front row, bridge cables,
  bridge, street) and each sheet is composited with its shadow when the window
  size changes. Moving parts (cars, the train, boats, the plane, birds, the crane
  load) are drawn on a work layer per band and composited with a live shadow; the
  river is made of paper wave strips that roll across. Lights are drawn after the
  shadows and ADD light (they brighten what is under them, like real light).

  Seasons: SUMMER (deep blue, lush green; fireworks over the river at night),
  RAINY (grey overcast sheets, wet dark street with puddles, rain, ripples,
  lightning, light reflections on the wet road) and WINTER (pale cold sky, snow
  caps on every roof and setback, snowy sidewalks, bare trees with string lights
  at night, slush, ice floes on the river, falling snow). A season changes the
  palettes and re-cuts the static sheets; the old picture fades out on top.

  The picture is laid out in a 1600 x 900 "design space" (landscape) and scaled
  to fit the window; the skyline, the bridge, the river and the street are cut
  for the whole visible range, so they always run past both window edges.

  Back to front: sky (sun / moon), stars, clouds, far city, Manhattan (two rows
  of towers, Empire State, Chrysler, One WTC, a crane, the Statue of Liberty),
  window lights, landmark lights, river with waves and light reflections, a
  suspension bridge with its cable lights and traffic and a subway train, boats,
  the street with lamps, a traffic signal and cars that stop at red, a plane,
  birds and the caption.

  Time of day: three palettes (morning, day, night). Every static part is cut
  once per window size for each palette; switching fades from one set to the
  other. The lights (windows, bridge bulbs, lamp pools) are separate sprites
  faded in by the "night" amount of the current palette, and everything that
  moves (traffic, beacons, boats, the train) uses that amount for its lights.

  TCityScene holds the state and every read-only resource, so the worker threads
  only read it. TPainter renders one horizontal band of the frame; one painter per
  worker thread. In vector mode the painter writes SVG instead of pixels. }

{$mode objfpc}{$H+}
{$INLINE ON}

interface

uses
  Classes, SysUtils, StrUtils, Math, Graphics, BGRABitmap, BGRABitmapTypes,
  BGRAGradientScanner, uRenderPool, uSvgRecorder;

const
  DesignW = 1600;
  DesignH = 900;
  FarBaseY = 590;    // distant skyline stands here
  CityBaseY = 606;   // Manhattan meets the river
  RiverBotY = 742;
  DeckY = 662;       // bridge road
  TowerTopY = 440;
  Tower1X = 400;
  Tower2X = 1210;
  WalkTopY = 742;    // far sidewalk
  RoadTopY = 770;
  RoadMidY = 813;
  RoadBotY = 858;
  SignalTop = 632;   // top of the signal head
  SignalX = 930;     // traffic signal and stop lines
  LibertyX = 150;    // Statue of Liberty (in the river layer)
  LibertyBase = 640;
  LibertyK = 1.55;   // her size
  SpriteKinds = 1;   // kept for the frame renderer (no round sprites in this scene)
  MaxDepth = 0.9;    // deepest live paper shadow (sets the band work layer margins)
  ModeCount = 3;
  ModeNames: array[0..2] of string = ('Morning', 'Day', 'Night');
  ModeNight: array[0..2] of Single = (0.32, 0, 1);    // how much the lights are on
  ModeShade: array[0..2] of Single = (0.86, 1, 0.42); // brightness of lit bodies
  SeasonCount = 3;
  SeasonNames: array[0..2] of string = ('Summer', 'Rainy', 'Winter');

type
  TLayerId = (lySky, lyStars, lyClouds, lyFarCity, lyCity, lyWindowLights, lyLandmarkLights,
    lyRiver, lyReflections, lyBridge, lyBridgeLights, lyBridgeTraffic, lyBoats, lyStreet,
    lyStreetLights, lyTraffic, lyPlane, lyBirds, lyWeather, lyCaption);

const
  LayerNames: array[TLayerId] of string = ('Sky', 'Stars', 'Clouds', 'Far city',
    'Manhattan', 'Window lights', 'Landmark lights', 'River', 'Reflections', 'Bridge',
    'Bridge lights', 'Bridge traffic', 'Boats', 'Street', 'Street lights', 'Traffic',
    'Plane', 'Birds', 'Weather', 'Caption');
  LayerKinds: array[TLayerId] of string = ('paper x3', 'vector', 'paper sprites x3',
    'paper x3', 'paper x3+live', 'light sprite+vector', 'light', 'paper x3+strips', 'light',
    'paper x3', 'light sprite', 'live paper+light', 'live paper+light', 'paper x3+light',
    'light sprite', 'live paper+light', 'live paper+light', 'live paper', 'live', 'static');
  { paper shadow depth of each layer (static sheets use their own depths, see Notes) }
  LayerDepth: array[TLayerId] of Single = (0.3, 0, 0.5, 0.3, 0.5, 0, 0, 0.35, 0, 0.8, 0,
    0.35, 0.6, 0.7, 0, 0.8, 0.6, 0.5, 0, 0);
  LayerNotes: array[TLayerId] of string = (
    '7 wavy paper bands + paper rings around the sun (morning low left, day high right) or moon',
    '260 stars twinkling, only at night',
    '7 two-sheet paper clouds with shadows, coloured for the time of day, from both sides',
    'Distant skyline: two paper rows',
    'Sheets: back row (0.45), landmarks (0.6), front row (0.75); the crane load swings (live shadow)',
    'Thousands of lit windows with a soft bloom, faded in at night, 90 switching on and off',
    'Empire State floodlights changing colour, Chrysler crown, WTC beacon, red roof beacons, crane, torch',
    'Water + 4 paper wave strips rolling both ways; Statue of Liberty sheet (0.6) in front',
    'Shimmering light columns under the city at night, sun glitter by day',
    'Sheets: cables / suspenders / stays (0.25), towers and deck (0.8)',
    'Bulbs along the cables and deck lamps, faded in at night',
    'Cars both ways with head / tail lights, a subway train with lit windows and headlight',
    'Ferry, tug and sailboat; cabin and navigation lights reflected in the water',
    'Road; sheets: far side with wall, lamps, trees, signal (0.7), near sidewalk (0.5)',
    'Lamp heads and light pools on the road and sidewalk, faded in at night',
    'Paper cars stop at red and queue; brake lights, headlight beams and pools, red road glow',
    'Plane crossing with contrail by day, blinking navigation lights at night',
    'Flocks of birds by day (not in the rain)',
    'Rain + ripples + lightning (rainy), snowfall (winter), fireworks (summer night)',
    'Title card with hotkeys');

  PaletteNames: array[0..23] of string = ('Night sky top', 'Night sky glow', 'Day sky top',
    'Day horizon', 'Morning sky top', 'Morning horizon', 'Sun', 'Moon', 'Facade day',
    'Glass day', 'Facade night', 'Window warm', 'Window white', 'Window cool',
    'Beacon red', 'Empire red', 'Empire blue', 'Bridge stone', 'Cable bulbs', 'Water day',
    'Water night', 'Asphalt', 'Taxi', 'Headlight');
  PaletteHex: array[0..23] of string = ('#050918', '#4A3A62', '#2F74CC', '#BEE3F7',
    '#5F86C2', '#F7B98B', '#FFF4C8', '#F2EED8', '#C9C6C0', '#9FC3E6', '#1A1E33', '#FFD58A',
    '#FFF1D0', '#CFE6FF', '#FF2A1A', '#E8303A', '#3A6BFF', '#B09A80', '#FFE6A8', '#3D7FB5',
    '#0D1430', '#55565C', '#F7C21B', '#FFF6DA');

type
  TPal = record
    SkyTop, SkyBot, Glow, SunC, Far, Haze, Glass, Win, Water1, Water2, Road, Walk,
    Stone, Cable, Tree, Liberty, CloudLit, CloudShade: TBGRAPixel;
    Facade: array[0..3] of TBGRAPixel;
    SunX, SunY, SunR: Single;
    Moon: Boolean;
    Snow: TBGRAPixel;      // winter: snow on roofs, sidewalks, trees
    SunHidden: Boolean;    // rainy: no sun / moon disc behind the overcast
  end;

  TBuilding = record
    X, W, H, BaseY, Var_: Single;
    Tone, Tiers, Roof: Integer;
    TierInset, TierH: array[0..1] of Single;
    LitProb: Single;
    Back: Boolean;
  end;

  TCloud = record
    Puffs: array of Single;  // x, y, r triples
    MinX, MaxX, MinY, MaxY, OX, Speed: Single;
    Sprite: array[0..2] of TBGRABitmap;
    Svg: array[0..2] of string;
  end;

  TCar = record
    X, Speed, Cruise, Len, H: Single;
    Lane, Kind: Integer;    // lane 0 far (to the left), 1 near (to the right)
    Color: TBGRAPixel;
    Brake: Boolean;         // braking or standing: brake lights on
  end;

  TSmallCar = record
    X, Speed: Single;
    Dir: Integer;
    Color: TBGRAPixel;
  end;

  TBoat = record
    X, Y, Speed, Size: Single;
    Kind: Integer;           // 0 ferry, 1 tug, 2 sailboat
  end;

  TFlicker = record
    X, Y, W, H, Rate, Phase: Single;
    C: TBGRAPixel;
  end;

  TRefl = record
    X: Single;
    C: TBGRAPixel;
    Strength: Single;
  end;

  TStar = record
    X, Y, R, Phase: Single;
  end;

  TBird = record
    X, Y, VX, Size, Phase: Single;
  end;

  TCityScene = class;

  TDrawProc = procedure(B: TBGRABitmap) of object;

  { TPainter: renders frame rows into a band bitmap. One per worker thread. }

  TPainter = class
  private
    FScene: TCityScene;
    FLayer: TBGRABitmap;
    FOrgX, FOrgY: Single;
    FTargetH: Integer;
    FPts: array of TPointF;
    FSvg: TSvgRecorder;
    FRaster: Boolean;
    FLayerTop: Integer;       // work layer covers frame rows [FLayerTop, FLayerTop + height)
    FRowA, FRowB: Integer;    // work layer rows in use (cleared by BeginLayer, read by CompositeLayer)
    FSvgMark: Integer;
    FPart: Integer;           // live paper layers: 0 = the paper (shadowed), 1 = its lights
    FShadow, FBlurTmp, FRow: array of Single;
    FXIdx: array of Integer;
    FXFrac: array of Single;
    procedure BeginLayer;
    procedure CompositeLayer(Dest: TBGRABitmap; DestTop: Integer; Depth: Single);
    procedure SvgLayerEnd(Depth: Single);
    function P(X, Y: Single): TPointF; inline;
    function S(V: Single): Single; inline;
    function RowsHit(Y0, Y1: Single): Boolean; inline;
    procedure TargetBand(ATop, AHeight: Integer);
    procedure DPoly(B: TBGRABitmap; const Pts: array of TPointF; C: TBGRAPixel);
    procedure DPolyG(B: TBGRABitmap; const Pts: array of TPointF; const G: TGrad);
    procedure DEllipse(B: TBGRABitmap; X, Y, RX, RY: Single; C: TBGRAPixel);
    procedure DEllipseG(B: TBGRABitmap; X, Y, RX, RY: Single; const G: TGrad);
    procedure DPolyLine(B: TBGRABitmap; const Pts: array of TPointF; C: TBGRAPixel; W: Single);
    procedure DLine(B: TBGRABitmap; X1, Y1, X2, Y2: Single; C: TBGRAPixel; W: Single);
    procedure DRect(B: TBGRABitmap; X1, Y1, X2, Y2: Single; C: TBGRAPixel);  // design coords, pixel aligned
    procedure DRadialRect(B: TBGRABitmap; X1, Y1, X2, Y2: Integer; C1, C2: TBGRAPixel;
      Ctr, Edge: TPointF);
    procedure Glow(B: TBGRABitmap; X, Y, R: Single; C: TBGRAPixel);  // design coords
    procedure Box(B: TBGRABitmap; X1, Y1, X2, Y2: Single; C: TBGRAPixel);  // design coords, AA
    { dynamic parts }
    procedure DrawStars(Dest: TBGRABitmap);
    procedure DrawClouds(Dest: TBGRABitmap);
    procedure DrawCraneLoad(Dest: TBGRABitmap);
    procedure DrawFlicker(Dest: TBGRABitmap);
    procedure DrawLandmarkLights(Dest: TBGRABitmap);
    procedure DrawWaves(Dest: TBGRABitmap);
    procedure DrawReflections(Dest: TBGRABitmap);
    procedure DrawBridgeTraffic(Dest: TBGRABitmap);
    procedure DrawBoats(Dest: TBGRABitmap);
    procedure DrawSignal(Dest: TBGRABitmap);
    procedure DrawCar(Dest: TBGRABitmap; const C: TCar);
    procedure DrawTraffic(Dest: TBGRABitmap);
    procedure DrawPlane(Dest: TBGRABitmap);
    procedure DrawBirds(Dest: TBGRABitmap);
    procedure DrawWeather(Dest: TBGRABitmap);
    { static cut (per palette) }
    procedure CutBuilding(B: TBGRABitmap; const Bd: TBuilding; const Pal: TPal);
    procedure CutLandmarks(B: TBGRABitmap; const Pal: TPal);
    procedure CutBridge(B: TBGRABitmap; const Pal: TPal; Part: Integer);
    procedure CutLiberty(B: TBGRABitmap; const Pal: TPal);
    procedure HDash(B: TBGRABitmap; X, Y, Len, Thick: Single; C: TBGRAPixel);
    procedure RainStreak(B: TBGRABitmap; X, Y, DX, Len, Thick: Single; C: TBGRAPixel);
    procedure EdgeFill(B: TBGRABitmap; const Edge: array of TPointF; ShiftX, Off, Thick, YBot: Single;
      C: TBGRAPixel);
    procedure CutStreet(B: TBGRABitmap; const Pal: TPal; Part: Integer);
  public
    LayerMs: array[TLayerId] of Double;
    constructor Create(AScene: TCityScene);
    destructor Destroy; override;
    procedure ResetStats;
    procedure RenderBand(Dest: TBGRABitmap; ATop: Integer);
  end;

  { TCityScene }

  TCityScene = class
  private
    FWidth, FHeight: Integer;
    FVisL, FVisR: Single;
    FScale, FOffX, FOffY: Single;
    FPal: array[0..2] of TPal;
    { static parts per palette, cropped to their rows }
    FSky, FFar, FCity, FRiver, FBridge, FStreet: array[0..2] of TBGRABitmap;
    FFarPos, FCityPos, FRiverPos, FBridgePos, FStreetPos: TPoint;
    FSvgSky, FSvgFar, FSvgCity, FSvgRiver, FSvgBridge, FSvgStreet: array[0..2] of string;
    { lights, faded in by the night amount }
    FWinLights, FBridgeLights, FStreetGlow: TBGRABitmap;
    FWinPos, FBridgeLPos, FGlowPos: TPoint;
    FSvgWinLights, FSvgBridgeLights, FSvgStreetGlow: string;
    FCaption: TBGRABitmap;
    FSvgCaption: string;
    FAcc: TBGRABitmap;               // static cut: the sheets of one part are stacked here
    FLib: array[0..2] of TBGRABitmap; // Statue of Liberty sheet (in front of the waves)
    FLibPos: TPoint;
    FSvgLib: array[0..2] of string;
    FCutter: TPainter;
    FRecordSvg: Boolean;
    FStaticSvg: TSvgRecorder;
    FSprites: array[0..SpriteKinds - 1] of array of TBGRABitmap;
    { scene content }
    FBuildings: array of TBuilding;
    FFarRects: array of TRectF;
    FBeacons: array of TPointF;       // red roof beacons (design)
    FFlicker: array of TFlicker;
    FRefl: array of TRefl;
    FStars: array of TStar;
    FClouds: array of TCloud;
    FLamps: array of Single;          // lamp post x (design)
    FCars: array of TCar;
    FBridgeCars: array of TSmallCar;
    FBoats: array of TBoat;
    FBirds: array of TBird;
    FTrainX, FTrainWait: Single;
    FPlaneX, FPlaneY, FPlaneWait: Single;
    FTime: Single;
    { time of day }
    FFrom, FTo: Integer;
    FBlend: Single;                   // 0 = palette FFrom, 1 = palette FTo
    FAuto: Boolean;
    FAutoTimer: Single;
    FShowCaption: Boolean;
    { season }
    FSeason, FPendingSeason: Integer;
    FPendingFade: Boolean;
    FSnap: TBGRABitmap;               // the picture before a season change, fading out
    FSnapFade: Single;
    FFlash, FFlashT, FFlashNext: Single;  // lightning
    FBolt: array of TPointF;
    FBoltOn: Boolean;
    procedure SeasonTint(var Pl: TPal; M: Integer);
    procedure ApplySeason;
    function P(X, Y: Single): TPointF;
    function S(V: Single): Single;
    procedure MakePalettes;
    procedure Generate;
    procedure AddCloud(Index: Integer; CX, CY, W, H, Speed: Single);
    procedure SpawnCar(var C: TCar; Lane: Integer; X: Single);
    procedure FreeResources;
    function Crop(Y0, Y1: Single; out Pos: TPoint): TBGRABitmap;
    function TakeSvg(Mark: Integer): string;
    procedure RenderStatic;
    procedure Grain(B: TBGRABitmap);
    procedure CutCloudSprites;
    function SignalState: Integer;   // 0 green, 1 yellow, 2 red
    procedure UpdateTraffic(DT: Single);
  public
    LayerOn: array[TLayerId] of Boolean;
    TransparentBack: Boolean;
    StaticMs: Double;
    StaticCount: Integer;
    AutoSeconds: Single;              // time per palette in auto mode
    FadeSeconds: Single;              // length of a palette change
    constructor Create;
    destructor Destroy; override;
    procedure Resize(AWidth, AHeight: Integer);
    function SpriteJobCount: Integer;
    procedure SpriteJob(AIndex, AWorker: Integer);
    procedure Update(DT: Single);
    procedure Prepare;
    procedure CopyStateFrom(Src: TCityScene);
    procedure RenderSvg(Svg: TSvgRecorder);
    { time of day }
    procedure SetMode(AMode: Integer);          // fades
    procedure SetModeInstant(AMode: Integer);
    { season: applied in Prepare (the workers are idle there); AFade fades the
      old picture out, without it the change is instant }
    procedure SetSeason(ASeason: Integer; AFade: Boolean = True);
    function Night: Single;                     // 0 day .. 1 night, blended
    function Shade: Single;                     // brightness of lit bodies, blended
    function CurrentMode: Integer;              // the palette with more weight
    function SpriteCount: Integer;
    function SpriteBytes: Int64;
    function StaticBytes: Int64;
    function DescribeParams: string;
    function CarCount: Integer;
    function WindowLightCount: Integer;
    property ShowCaption: Boolean read FShowCaption write FShowCaption;
    property AutoCycle: Boolean read FAuto write FAuto;
    property Season: Integer read FSeason;
    property ModeFrom: Integer read FFrom;
    property ModeTo: Integer read FTo;
    property Blend: Single read FBlend;
    property VectorStatic: Boolean read FRecordSvg write FRecordSvg;
    property Time: Single read FTime;
    property Scale: Single read FScale;
    property OffX: Single read FOffX;
    property OffY: Single read FOffY;
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    property VisL: Single read FVisL;
    property VisR: Single read FVisR;
  end;

implementation

var
  WinLit: array[0..4] of TBGRAPixel;

function Hex(const S: string): TBGRAPixel;
begin
  Result := StrToBGRA(S);
end;

function WithAlpha(C: TBGRAPixel; A: Integer): TBGRAPixel; inline;
begin
  Result := C;
  Result.alpha := EnsureRange(A, 0, 255);
end;

function Darken(C: TBGRAPixel; K: Single): TBGRAPixel;
begin
  Result.red := EnsureRange(Round(C.red * K), 0, 255);
  Result.green := EnsureRange(Round(C.green * K), 0, 255);
  Result.blue := EnsureRange(Round(C.blue * K), 0, 255);
  Result.alpha := C.alpha;
end;

function Mix(A, B: TBGRAPixel; T: Single): TBGRAPixel;
begin
  Result.red := Round(A.red + (B.red - A.red) * T);
  Result.green := Round(A.green + (B.green - A.green) * T);
  Result.blue := Round(A.blue + (B.blue - A.blue) * T);
  Result.alpha := Round(A.alpha + (B.alpha - A.alpha) * T);
end;

function RandRange(A, B: Single): Single;
begin
  Result := A + Random * (B - A);
end;

{ deterministic 0..1 noise for an integer key (no state, thread safe) }
function Hash01(K: Integer): Single;
var
  X: LongWord;
begin
  X := LongWord(K) * 2654435761;
  X := X xor (X shr 15);
  X := X * 2246822519;
  X := X xor (X shr 13);
  Result := (X and $FFFFFF) / $1000000;
end;

{ fractional part that is always 0..1 (also for negative values) }
function PFrac(V: Single): Single; inline;
begin
  Result := V - Floor(V);
end;

function GreyMix(C: TBGRAPixel; T: Single): TBGRAPixel;
var
  L: Integer;
begin
  L := (C.red * 30 + C.green * 59 + C.blue * 11) div 100;
  Result := Mix(C, BGRA(L, L, L, C.alpha), T);
end;

{ the skyline height envelope: midtown and downtown clusters }
function Env(X: Single): Single;
begin
  Result := 120 + 170 * Exp(-Sqr((X - 640) / 300)) + 210 * Exp(-Sqr((X - 1170) / 230)) +
    70 * Exp(-Sqr((X - 260) / 200)) + 60 * Exp(-Sqr((X - 1650) / 260));
end;

{ main cable of the bridge: y at x (front cable) }
function CableY(X: Single): Single;
var
  T, Mid: Single;
begin
  if X <= Tower1X + 35 then
  begin
    T := EnsureRange((Tower1X + 35 - X) / 700, 0, 1);
    Result := TowerTopY + 10 + (DeckY - 14 - TowerTopY - 10) * (1 - Sqr(1 - T));
  end
  else if X >= Tower2X + 35 then
  begin
    T := EnsureRange((X - Tower2X - 35) / 700, 0, 1);
    Result := TowerTopY + 10 + (DeckY - 14 - TowerTopY - 10) * (1 - Sqr(1 - T));
  end
  else
  begin
    Mid := (Tower1X + Tower2X) / 2 + 35;
    T := (X - Mid) / ((Tower2X - Tower1X) / 2);
    Result := DeckY - 26 - (DeckY - 26 - TowerTopY - 10) * Sqr(T);
  end;
end;

{ One box-blur pass over a W x H single-channel buffer (horizontal then vertical). }
procedure BoxBlur(var A, Tmp: array of Single; W, H, R: Integer);
var
  X, Y, I: Integer;
  Sum, Inv: Single;
begin
  Inv := 1 / (2 * R + 1);
  for Y := 0 to H - 1 do
  begin
    Sum := 0;
    for I := 0 to Min(R, W - 1) do
      Sum := Sum + A[Y * W + I];
    for X := 0 to W - 1 do
    begin
      Tmp[Y * W + X] := Sum * Inv;
      if X + R + 1 < W then Sum := Sum + A[Y * W + X + R + 1];
      if X - R >= 0 then Sum := Sum - A[Y * W + X - R];
    end;
  end;
  for X := 0 to W - 1 do
  begin
    Sum := 0;
    for I := 0 to Min(R, H - 1) do
      Sum := Sum + Tmp[I * W + X];
    for Y := 0 to H - 1 do
    begin
      A[Y * W + X] := Sum * Inv;
      if Y + R + 1 < H then Sum := Sum + Tmp[(Y + R + 1) * W + X];
      if Y - R >= 0 then Sum := Sum - Tmp[(Y - R) * W + X];
    end;
  end;
end;

{ Row Y of a bitmap without going through BGRABitmap's getters (thread safe reads). }
function RowPtr(B: TBGRABitmap; Y: Integer): PBGRAPixel; inline;
begin
  if B.LineOrder = riloTopToBottom then
    Result := B.Data + Y * B.Width
  else
    Result := B.Data + (B.Height - 1 - Y) * B.Width;
end;

{ Draws Src at (X, Y) on Dest with an extra opacity (alpha "over", Dest may be
  transparent). Src is only read, so any number of threads can draw it. }
procedure BlendBitmap(Dest: TBGRABitmap; X, Y: Integer; Src: TBGRABitmap; Opacity: Integer = 255);
var
  SX0, SY0, SX1, SY1, YY, XX, SA, DA, W1, W2, WS: Integer;
  S, D: PBGRAPixel;
begin
  if (Src = nil) or (Opacity <= 0) then Exit;
  SX0 := Max(0, -X);
  SY0 := Max(0, -Y);
  SX1 := Min(Src.Width, Dest.Width - X);
  SY1 := Min(Src.Height, Dest.Height - Y);
  if (SX1 <= SX0) or (SY1 <= SY0) then Exit;
  for YY := SY0 to SY1 - 1 do
  begin
    S := RowPtr(Src, YY) + SX0;
    D := RowPtr(Dest, Y + YY) + X + SX0;
    for XX := SX0 to SX1 - 1 do
    begin
      SA := S^.alpha;
      if Opacity < 255 then SA := SA * Opacity div 255;
      if SA = 255 then
        D^ := S^
      else if SA > 0 then
      begin
        DA := D^.alpha;
        if DA = 255 then
        begin
          W2 := 255 - SA;
          D^.red := (S^.red * SA + D^.red * W2) div 255;
          D^.green := (S^.green * SA + D^.green * W2) div 255;
          D^.blue := (S^.blue * SA + D^.blue * W2) div 255;
        end
        else
        begin
          W1 := SA * 255;
          W2 := DA * (255 - SA);
          WS := W1 + W2;
          D^.red := (S^.red * W1 + D^.red * W2) div WS;
          D^.green := (S^.green * W1 + D^.green * W2) div WS;
          D^.blue := (S^.blue * W1 + D^.blue * W2) div WS;
          D^.alpha := WS div 255;
        end;
      end;
      Inc(S);
      Inc(D);
    end;
  end;
end;

{ ====================================================================== }
{ TPainter                                                               }
{ ====================================================================== }

constructor TPainter.Create(AScene: TCityScene);
begin
  inherited Create;
  FScene := AScene;
  FLayer := TBGRABitmap.Create(1, 1);
  FRaster := True;
  SetLength(FPts, 64);
end;

destructor TPainter.Destroy;
begin
  FLayer.Free;
  inherited Destroy;
end;

procedure TPainter.ResetStats;
begin
  FillChar(LayerMs, SizeOf(LayerMs), 0);
end;

function TPainter.P(X, Y: Single): TPointF;
begin
  Result.X := FOrgX + X * FScene.FScale;
  Result.Y := FOrgY + Y * FScene.FScale;
end;

function TPainter.S(V: Single): Single;
begin
  Result := V * FScene.FScale;
end;

function TPainter.RowsHit(Y0, Y1: Single): Boolean;
begin
  Result := (FOrgY + Y1 * FScene.FScale >= -2) and (FOrgY + Y0 * FScene.FScale <= FTargetH + 2);
end;

procedure TPainter.TargetBand(ATop, AHeight: Integer);
begin
  FOrgX := FScene.FOffX;
  FOrgY := FScene.FOffY - ATop;
  FTargetH := AHeight;
end;

procedure TPainter.BeginLayer;
begin
  FOrgX := FScene.FOffX;
  FOrgY := FScene.FOffY - FLayerTop;
  if FRaster then
  begin
    FRowA := EnsureRange(FRowA, 0, FLayer.Height);
    FRowB := EnsureRange(FRowB, FRowA, FLayer.Height);
    if (FRowA = 0) and (FRowB = FLayer.Height) then
      FLayer.FillTransparent
    else if FRowB > FRowA then
      FLayer.FillRect(0, FRowA, FLayer.Width, FRowB, BGRAPixelTransparent, dmSet);
    FTargetH := FLayer.Height;
  end
  else
    FTargetH := FScene.FHeight;
  if FSvg <> nil then FSvgMark := FSvg.Mark;
end;

{ vector mode: everything since BeginLayer becomes one group with the paper shadow }
procedure TPainter.SvgLayerEnd(Depth: Single);
var
  Content: string;
begin
  Content := FSvg.Take(FSvgMark);
  if Content = '' then Exit;
  if Depth > 0 then
    FSvg.Raw('<g filter="url(#' + FSvg.DropShadow(S(3) * Depth, S(6) * Depth, S(7) * Depth * 0.5,
      90 / 255) + ')">' + LineEnding + Content + '</g>')
  else
    FSvg.Raw('<g>' + LineEnding + Content + '</g>');
end;

{ Lays the work layer on Dest with a soft paper shadow, in one pass.
  Shadow = layer alpha sampled every 4th pixel (grid aligned to frame rows), box
  blurred twice, then bilinearly stretched back while blending. Only the bounding
  box of what the layer holds is touched. Works on opaque and transparent Dest
  (Dest may be narrower than the layer: cloud sprites). }
procedure TPainter.CompositeLayer(Dest: TBGRABitmap; DestTop: Integer; Depth: Single);
const
  F = 4;
  Strength = 90 / 255;
var
  LW, LH, DH, SW, SH, X, Y, R, DX, DY, LX, LY, SY0, X0, X1, Y0, Y1, SA, LA, Inv,
  Pad, BX0, BX1, BY0, BY1, W1, W2, WS: Integer;
  FY, V: Single;
  Src, Dst, L: PBGRAPixel;
begin
  if FSvg <> nil then SvgLayerEnd(Depth);
  if not FRaster then Exit;
  LW := FLayer.Width;
  LH := FLayer.Height;
  DH := Dest.Height;
  BX0 := MaxInt; BX1 := -1; BY0 := MaxInt; BY1 := -1;
  SW := LW div F + 2;
  SH := LH div F + 2;
  if Length(FShadow) < SW * SH then
  begin
    SetLength(FShadow, SW * SH);
    SetLength(FBlurTmp, SW * SH);
  end;
  for Y := 0 to SH - 1 do
  begin
    LY := Y * F;
    if (LY >= LH) or (LY < FRowA) or (LY >= FRowB) then
    begin
      for X := 0 to SW - 1 do FShadow[Y * SW + X] := 0;
      Continue;
    end;
    Src := RowPtr(FLayer, LY);
    for X := 0 to SW - 1 do
    begin
      LX := X * F;
      if (LX < LW) and ((Src + LX)^.alpha > 0) then
      begin
        FShadow[Y * SW + X] := (Src + LX)^.alpha * Strength;
        if X < BX0 then BX0 := X;
        if X > BX1 then BX1 := X;
        if Y < BY0 then BY0 := Y;
        if Y > BY1 then BY1 := Y;
      end
      else
        FShadow[Y * SW + X] := 0;
    end;
  end;
  if BX1 < 0 then Exit;  // empty layer
  R := Max(1, Round(S(7) * Depth / F));
  if Depth > 0 then
  begin
    BoxBlur(FShadow, FBlurTmp, SW, SH, R);
    BoxBlur(FShadow, FBlurTmp, SW, SH, R);
  end
  else
    FillChar(FShadow[0], SW * SH * SizeOf(Single), 0);

  DX := Round(S(3) * Depth);
  DY := Round(S(6) * Depth);
  Pad := (2 * R + 2) * F;
  X0 := Max(0, BX0 * F - Pad);
  X1 := Min(Min(LW, Dest.Width), BX1 * F + DX + Pad);
  Y0 := Max(0, FLayerTop + BY0 * F - Pad - DestTop);
  Y1 := Min(DH, FLayerTop + BY1 * F + DY + Pad - DestTop);
  if (X1 <= X0) or (Y1 <= Y0) then Exit;
  if Length(FXIdx) < LW then
  begin
    SetLength(FXIdx, LW);
    SetLength(FXFrac, LW);
  end;
  for X := X0 to X1 - 1 do
  begin
    V := (X - DX) / F;
    FXIdx[X] := Floor(V);
    FXFrac[X] := V - FXIdx[X];
  end;
  if Length(FRow) < SW then SetLength(FRow, SW);
  L := nil;
  for Y := Y0 to Y1 - 1 do
  begin
    FY := (DestTop + Y - DY - FLayerTop) / F;
    SY0 := Floor(FY);
    FY := FY - SY0;
    for X := 0 to SW - 1 do
    begin
      V := 0;
      if (SY0 >= 0) and (SY0 < SH) then V := FShadow[SY0 * SW + X] * (1 - FY);
      if (SY0 + 1 >= 0) and (SY0 + 1 < SH) then V := V + FShadow[(SY0 + 1) * SW + X] * FY;
      FRow[X] := V;
    end;
    LY := DestTop + Y - FLayerTop;
    if (LY >= FRowA) and (LY < FRowB) and (LY < LH) then Src := RowPtr(FLayer, LY) else Src := nil;
    Dst := RowPtr(Dest, Y);
    for X := X0 to X1 - 1 do
    begin
      LX := FXIdx[X];
      V := 0;
      if (LX >= 0) and (LX < SW) then V := FRow[LX] * (1 - FXFrac[X]);
      if (LX + 1 >= 0) and (LX + 1 < SW) then V := V + FRow[LX + 1] * FXFrac[X];
      SA := Round(V);
      LA := 0;
      if Src <> nil then
      begin
        L := Src + X;
        LA := L^.alpha;
      end;
      if (SA = 0) and (LA = 0) then Continue;
      with (Dst + X)^ do
      begin
        if LA = 255 then
        begin
          red := L^.red;
          green := L^.green;
          blue := L^.blue;
          alpha := 255;
          Continue;
        end;
        if alpha = 255 then
        begin
          if SA > 0 then
          begin
            Inv := 255 - SA;
            red := red * Inv div 255;
            green := green * Inv div 255;
            blue := blue * Inv div 255;
          end;
          if LA > 0 then
          begin
            Inv := 255 - LA;
            red := (L^.red * LA + red * Inv) div 255;
            green := (L^.green * LA + green * Inv) div 255;
            blue := (L^.blue * LA + blue * Inv) div 255;
          end;
        end
        else
        begin
          if SA > 0 then
          begin
            W2 := alpha * (255 - SA);
            WS := SA * 255 + W2;
            red := red * W2 div WS;
            green := green * W2 div WS;
            blue := blue * W2 div WS;
            alpha := WS div 255;
          end;
          if LA > 0 then
          begin
            W1 := LA * 255;
            W2 := alpha * (255 - LA);
            WS := W1 + W2;
            red := (L^.red * W1 + red * W2) div WS;
            green := (L^.green * W1 + green * W2) div WS;
            blue := (L^.blue * W1 + blue * W2) div WS;
            alpha := WS div 255;
          end;
        end;
      end;
    end;
  end;
  Dest.InvalidateBitmap;
end;

{ ---------- primitives: pixels, SVG, or both ---------- }

procedure TPainter.DPoly(B: TBGRABitmap; const Pts: array of TPointF; C: TBGRAPixel);
begin
  if FSvg <> nil then FSvg.Poly(Pts, C);
  if FRaster then B.FillPolyAntialias(Pts, C);
end;

procedure TPainter.DPolyG(B: TBGRABitmap; const Pts: array of TPointF; const G: TGrad);
var
  Sc: TBGRAGradientScanner;
begin
  if FSvg <> nil then FSvg.PolyFill(Pts, FSvg.Gradient(G));
  if FRaster then
  begin
    if G.Radial then
      Sc := TBGRAGradientScanner.Create(G.C1, G.C2, gtRadial, G.P1, G.P2, True)
    else
      Sc := TBGRAGradientScanner.Create(G.C1, G.C2, gtLinear, G.P1, G.P2, True);
    try
      B.FillPolyAntialias(Pts, Sc);
    finally
      Sc.Free;
    end;
  end;
end;

procedure TPainter.DEllipse(B: TBGRABitmap; X, Y, RX, RY: Single; C: TBGRAPixel);
begin
  if FSvg <> nil then FSvg.Ellipse(X, Y, RX, RY, C);
  if FRaster then B.FillEllipseAntialias(X, Y, RX, RY, C);
end;

procedure TPainter.DEllipseG(B: TBGRABitmap; X, Y, RX, RY: Single; const G: TGrad);
var
  Sc: TBGRAGradientScanner;
begin
  if FSvg <> nil then FSvg.EllipseFill(X, Y, RX, RY, FSvg.Gradient(G));
  if FRaster then
  begin
    if G.Radial then
      Sc := TBGRAGradientScanner.Create(G.C1, G.C2, gtRadial, G.P1, G.P2, True)
    else
      Sc := TBGRAGradientScanner.Create(G.C1, G.C2, gtLinear, G.P1, G.P2, True);
    try
      B.FillEllipseAntialias(X, Y, RX, RY, Sc);
    finally
      Sc.Free;
    end;
  end;
end;

procedure TPainter.DPolyLine(B: TBGRABitmap; const Pts: array of TPointF; C: TBGRAPixel; W: Single);
begin
  if FSvg <> nil then FSvg.PolyLine(Pts, C, W);
  if FRaster then B.DrawPolyLineAntialias(Pts, C, W);
end;

procedure TPainter.DLine(B: TBGRABitmap; X1, Y1, X2, Y2: Single; C: TBGRAPixel; W: Single);
begin
  if FSvg <> nil then FSvg.Line(X1, Y1, X2, Y2, C, W);
  if FRaster then B.DrawLineAntialias(X1, Y1, X2, Y2, C, W);
end;

procedure TPainter.DRect(B: TBGRABitmap; X1, Y1, X2, Y2: Single; C: TBGRAPixel);
var
  A, Z: TPointF;
  IX1, IY1, IX2, IY2: Integer;
begin
  A := P(X1, Y1);
  Z := P(X2, Y2);
  IX1 := Round(A.X); IY1 := Round(A.Y); IX2 := Max(IX1 + 1, Round(Z.X)); IY2 := Max(IY1 + 1, Round(Z.Y));
  if FSvg <> nil then
    if C.alpha = 255 then
      FSvg.Rect(IX1, IY1, IX2 - IX1, IY2 - IY1, '#' + IntToHex(C.red, 2) + IntToHex(C.green, 2) +
        IntToHex(C.blue, 2))
    else
      FSvg.Poly([PointF(IX1, IY1), PointF(IX2, IY1), PointF(IX2, IY2), PointF(IX1, IY2)], C);
  if FRaster then
    if C.alpha = 255 then B.FillRect(IX1, IY1, IX2, IY2, C, dmSet)
    else B.FillRect(IX1, IY1, IX2, IY2, C, dmDrawWithTransparency);
end;

procedure TPainter.DRadialRect(B: TBGRABitmap; X1, Y1, X2, Y2: Integer; C1, C2: TBGRAPixel;
  Ctr, Edge: TPointF);
begin
  if FSvg <> nil then
    FSvg.Rect(X1, Y1, X2 - X1, Y2 - Y1, FSvg.Gradient(MakeGrad(C1, C2, True, Ctr, Edge)));
  if FRaster then
    B.GradientFill(X1, Y1, X2, Y2, C1, C2, gtRadial, Ctr, Edge, dmDrawWithTransparency);
end;

{ a soft round glow (radial gradient to transparent) in design coordinates }
{ A light in design coordinates: radius R, colour C, strength C.alpha.
  On an opaque target it ADDS light ((1 - d^2)^2 falloff), so lamps brighten
  the paper under them instead of veiling it; on a transparent target (light
  sprites, layer export) it is blended normally. }
procedure TPainter.Glow(B: TBGRABitmap; X, Y, R: Single; C: TBGRAPixel);
var
  Q: TPointF;
  RP, RR, DY2, D2, F, Ia: Single;
  X0, X1, Y0, Y1, XX, YY, A, W1, W2, WS: Integer;
  D: PBGRAPixel;
begin
  if (C.alpha = 0) or (R <= 0) then Exit;
  if not RowsHit(Y - R, Y + R) then Exit;
  Q := P(X, Y);
  RP := Max(1, S(R));
  if FSvg <> nil then
    FSvg.EllipseFill(Q.X, Q.Y, RP, RP, FSvg.Gradient(MakeGrad(C, WithAlpha(C, 0), True, Q,
      PointF(Q.X + RP, Q.Y))));
  if not FRaster then Exit;
  X0 := Max(0, Floor(Q.X - RP));
  X1 := Min(B.Width - 1, Ceil(Q.X + RP));
  Y0 := Max(0, Floor(Q.Y - RP));
  Y1 := Min(B.Height - 1, Ceil(Q.Y + RP));
  if (X1 < X0) or (Y1 < Y0) then Exit;
  RR := 1 / (RP * RP);
  Ia := C.alpha / 255;
  for YY := Y0 to Y1 do
  begin
    DY2 := Sqr(YY + 0.5 - Q.Y) * RR;
    if DY2 >= 1 then Continue;
    D := RowPtr(B, YY) + X0;
    for XX := X0 to X1 do
    begin
      D2 := DY2 + Sqr(XX + 0.5 - Q.X) * RR;
      if D2 < 1 then
      begin
        F := 1 - D2;
        F := F * F * Ia;
        A := Round(F * 255);
        if A > 0 then
          if D^.alpha = 255 then
          begin
            W1 := D^.red + Round(C.red * F);
            if W1 > 255 then W1 := 255;
            D^.red := W1;
            W1 := D^.green + Round(C.green * F);
            if W1 > 255 then W1 := 255;
            D^.green := W1;
            W1 := D^.blue + Round(C.blue * F);
            if W1 > 255 then W1 := 255;
            D^.blue := W1;
          end
          else
          begin
            W1 := A * 255;
            W2 := D^.alpha * (255 - A);
            WS := W1 + W2;
            D^.red := (C.red * W1 + D^.red * W2) div WS;
            D^.green := (C.green * W1 + D^.green * W2) div WS;
            D^.blue := (C.blue * W1 + D^.blue * W2) div WS;
            D^.alpha := WS div 255;
          end;
      end;
      Inc(D);
    end;
  end;
end;

{ A short horizontal stroke (waves, reflections) in design coordinates: a pixel
  span blended straight into the band, the partly covered end pixels weighted.
  Much cheaper than an antialiased line for thousands of tiny strokes. }
procedure TPainter.HDash(B: TBGRABitmap; X, Y, Len, Thick: Single; C: TBGRAPixel);
var
  A, Z: TPointF;
  Y0, Y1, YY, XX, X0, X1, Al, W2: Integer;
  Cov: Single;
  D: PBGRAPixel;
begin
  if C.alpha = 0 then Exit;
  A := P(X, Y - Thick / 2);
  Z := P(X + Len, Y + Thick / 2);
  if (Z.Y < 0) or (A.Y > FTargetH) then Exit;
  if FSvg <> nil then FSvg.Poly([A, PointF(Z.X, A.Y), Z, PointF(A.X, Z.Y)], C);
  if not FRaster then Exit;
  Y0 := Max(0, Floor(A.Y));
  Y1 := Min(B.Height - 1, Max(Y0, Ceil(Z.Y) - 1));
  X0 := Max(0, Floor(A.X));
  X1 := Min(B.Width - 1, Ceil(Z.X) - 1);
  if (X1 < X0) or (Y0 > Y1) then Exit;
  for YY := Y0 to Y1 do
  begin
    // vertical coverage of this row
    Cov := Min(Z.Y, YY + 1) - Max(A.Y, YY);
    if Cov <= 0 then Continue;
    if Cov > 1 then Cov := 1;
    D := RowPtr(B, YY) + X0;
    for XX := X0 to X1 do
    begin
      if XX = X0 then Al := Round(C.alpha * Cov * Min(1, XX + 1 - A.X))
      else if XX = X1 then Al := Round(C.alpha * Cov * Min(1, Z.X - XX))
      else Al := Round(C.alpha * Cov);
      if Al > 0 then
      begin
        if Al > 255 then Al := 255;
        W2 := 255 - Al;
        D^.red := (C.red * Al + D^.red * W2) div 255;
        D^.green := (C.green * Al + D^.green * W2) div 255;
        D^.blue := (C.blue * Al + D^.blue * W2) div 255;
        if D^.alpha < 255 then D^.alpha := Al + D^.alpha * W2 div 255;
      end;
      Inc(D);
    end;
  end;
end;

{ Fills under a wavy edge, column by column (pixel coordinates; Edge sorted by
  x): from edge + Off down to edge + Off + Thick, or down to YBot when Thick <= 0.
  The top and bottom pixels get their coverage. Far cheaper than an antialiased
  polygon with hundreds of vertices; SVG gets the same shape as a polygon. }
procedure TPainter.EdgeFill(B: TBGRABitmap; const Edge: array of TPointF; ShiftX, Off, Thick, YBot: Single;
  C: TBGRAPixel);
var
  N, I, J, X0, X1, XX, YY, R0, R1, Al, W1, W2, WS: Integer;
  T, Yt, Yb, Cov: Single;
  Poly: array of TPointF;
  D: PBGRAPixel;
begin
  N := Length(Edge);
  if (N < 2) or (C.alpha = 0) then Exit;
  if FSvg <> nil then
  begin
    SetLength(Poly, 2 * N);
    for I := 0 to N - 1 do
    begin
      Poly[I] := PointF(Edge[I].X + ShiftX, Edge[I].Y + Off);
      if Thick > 0 then
        Poly[2 * N - 1 - I] := PointF(Edge[I].X + ShiftX, Edge[I].Y + Off + Thick)
      else
        Poly[2 * N - 1 - I] := PointF(Edge[I].X + ShiftX, YBot);
    end;
    FSvg.Poly(Poly, C);
  end;
  if not FRaster then Exit;
  X0 := Max(0, Ceil(Edge[0].X + ShiftX));
  X1 := Min(B.Width - 1, Floor(Edge[N - 1].X + ShiftX));
  J := 0;
  for XX := X0 to X1 do
  begin
    T := XX + 0.5 - ShiftX;
    while (J < N - 2) and (Edge[J + 1].X < T) do Inc(J);
    if Edge[J + 1].X = Edge[J].X then Yt := Edge[J].Y
    else Yt := Edge[J].Y + (Edge[J + 1].Y - Edge[J].Y) * (T - Edge[J].X) / (Edge[J + 1].X - Edge[J].X);
    Yt := Yt + Off;
    if Thick > 0 then Yb := Yt + Thick else Yb := YBot;
    if Yb <= Yt then Continue;
    R0 := Max(0, Floor(Yt));
    R1 := Min(B.Height - 1, Ceil(Yb) - 1);
    for YY := R0 to R1 do
    begin
      Cov := Min(Yb, YY + 1) - Max(Yt, YY);
      if Cov <= 0 then Continue;
      if Cov > 1 then Cov := 1;
      Al := Round(C.alpha * Cov);
      if Al <= 0 then Continue;
      D := RowPtr(B, YY) + XX;
      if Al >= 255 then
        D^ := C
      else if D^.alpha = 255 then
      begin
        W2 := 255 - Al;
        D^.red := (C.red * Al + D^.red * W2) div 255;
        D^.green := (C.green * Al + D^.green * W2) div 255;
        D^.blue := (C.blue * Al + D^.blue * W2) div 255;
      end
      else
      begin
        W1 := Al * 255;
        W2 := D^.alpha * (255 - Al);
        WS := W1 + W2;
        D^.red := (C.red * W1 + D^.red * W2) div WS;
        D^.green := (C.green * W1 + D^.green * W2) div WS;
        D^.blue := (C.blue * W1 + D^.blue * W2) div WS;
        D^.alpha := WS div 255;
      end;
    end;
  end;
end;

{ A steep thin stroke (rain) from (X, Y) to (X + DX, Y + Len), design coordinates:
  one short horizontal span per pixel row, its end pixels weighted by coverage. }
procedure TPainter.RainStreak(B: TBGRABitmap; X, Y, DX, Len, Thick: Single; C: TBGRAPixel);
var
  A, Z: TPointF;
  R0, R1, YY, XX, X0, X1, Al, W2: Integer;
  T, XC, HW, L, R, Cov: Single;
  D: PBGRAPixel;
begin
  if C.alpha = 0 then Exit;
  A := P(X, Y);
  Z := P(X + DX, Y + Len);
  if FSvg <> nil then FSvg.Line(A.X, A.Y, Z.X, Z.Y, C, Max(0.5, S(Thick)));
  if not FRaster then Exit;
  if Z.Y - A.Y < 0.5 then Exit;
  R0 := Max(0, Floor(A.Y));
  R1 := Min(B.Height - 1, Ceil(Z.Y) - 1);
  HW := Max(0.5, S(Thick)) / 2;
  for YY := R0 to R1 do
  begin
    T := (YY + 0.5 - A.Y) / (Z.Y - A.Y);
    if (T < 0) or (T > 1) then Continue;
    XC := A.X + T * (Z.X - A.X);
    L := XC - HW;
    R := XC + HW;
    X0 := Max(0, Floor(L));
    X1 := Min(B.Width - 1, Ceil(R) - 1);
    D := RowPtr(B, YY) + X0;
    for XX := X0 to X1 do
    begin
      Cov := Min(R, XX + 1) - Max(L, XX);
      if Cov > 0 then
      begin
        Al := Round(C.alpha * Min(1, Cov));
        W2 := 255 - Al;
        D^.red := (C.red * Al + D^.red * W2) div 255;
        D^.green := (C.green * Al + D^.green * W2) div 255;
        D^.blue := (C.blue * Al + D^.blue * W2) div 255;
        if D^.alpha < 255 then D^.alpha := Al + D^.alpha * W2 div 255;
      end;
      Inc(D);
    end;
  end;
end;

procedure TPainter.Box(B: TBGRABitmap; X1, Y1, X2, Y2: Single; C: TBGRAPixel);
begin
  DPoly(B, [P(X1, Y1), P(X2, Y1), P(X2, Y2), P(X1, Y2)], C);
end;

{ ---------- static cut ---------- }

{ A tower: main block, setbacks, a lit / shaded side, a window grid and a roof
  (antenna, water tower or a flat crown). }
procedure TPainter.CutBuilding(B: TBGRABitmap; const Bd: TBuilding; const Pal: TPal);
var
  K, Col, Row: Integer;
  X1, X2, Y1, Y2, Top, WX, WY, Shade: Single;
  Face, Side, Win: TBGRAPixel;
  Glass: Boolean;
begin
  Face := Pal.Facade[Bd.Tone];
  Face := Darken(Face, 1 + Bd.Var_);
  if Bd.Back then Face := Mix(Face, Pal.Haze, 0.35);
  Side := Darken(Face, 0.72);
  Glass := (Bd.Tone = 3);
  if Glass then Win := Pal.Glass else Win := Pal.Win;
  if Bd.Back then Win := Mix(Win, Pal.Haze, 0.3);
  Top := Bd.BaseY - Bd.H;
  for K := 0 to Bd.Tiers do
  begin
    if K = 0 then
    begin
      X1 := Bd.X; X2 := Bd.X + Bd.W; Y1 := Bd.BaseY - Bd.H; Y2 := Bd.BaseY;
    end
    else
    begin
      X1 := Bd.X + Bd.TierInset[K - 1] * Bd.W;
      X2 := Bd.X + Bd.W - Bd.TierInset[K - 1] * Bd.W;
      Y2 := Top;
      Y1 := Top - Bd.TierH[K - 1];
      Top := Y1;
    end;
    if K = 0 then Top := Y1;
    Box(B, X1, Y1, X2, Y2, Face);
    Shade := (X2 - X1) * 0.22;
    Box(B, X2 - Shade, Y1, X2, Y2, Side);
    if FScene.FSeason = 2 then  // snow on every roof and setback
      Box(B, X1 - 0.6, Y1 - 2.6, X2 + 0.6, Y1 + 1.4, Pal.Snow);
    // window grid
    WY := Y1 + 6;
    Row := 0;
    while WY + 5 < Y2 - 3 do
    begin
      WX := X1 + 3;
      Col := 0;
      while WX + 4 < X2 - 2 do
      begin
        if Glass then
          DRect(B, WX, WY, WX + 5, WY + 6, Darken(Win, 0.92 + 0.16 * Hash01(Round(WX * 7 + WY * 13))))
        else
          DRect(B, WX, WY, WX + 4, WY + 5, Win);
        WX := WX + 7;
        Inc(Col);
      end;
      WY := WY + 9;
      Inc(Row);
    end;
  end;
  // roof
  case Bd.Roof of
    1: begin  // antenna
         DLine(B, P(Bd.X + Bd.W / 2, Top).X, P(0, Top).Y, P(Bd.X + Bd.W / 2, 0).X,
           P(0, Top - 28).Y, Side, Max(0.7, S(1.5)));
       end;
    2: begin  // water tower
         Box(B, Bd.X + Bd.W * 0.3, Top - 12, Bd.X + Bd.W * 0.3 + 12, Top - 3, Darken(Pal.Stone, 0.7));
         DPoly(B, [P(Bd.X + Bd.W * 0.3 - 1, Top - 12), P(Bd.X + Bd.W * 0.3 + 6, Top - 18),
           P(Bd.X + Bd.W * 0.3 + 13, Top - 12)], Darken(Pal.Stone, 0.55));
         DLine(B, P(Bd.X + Bd.W * 0.3 + 2, Top - 3).X, P(0, Top - 3).Y, P(Bd.X + Bd.W * 0.3 + 2, 0).X,
           P(0, Top).Y, Side, Max(0.6, S(1)));
       end;
    3: begin  // crown
         DPoly(B, [P(Bd.X + 3, Top), P(Bd.X + Bd.W / 2, Top - Bd.W * 0.3), P(Bd.X + Bd.W - 3, Top)], Side);
       end;
  end;
end;

{ Empire State, Chrysler, One WTC, the crane and the Statue of Liberty. }
procedure TPainter.CutLandmarks(B: TBGRABitmap; const Pal: TPal);
var
  Face, Side, Win, Steel: TBGRAPixel;
  X, Y, Wd, Base: Single;
  I, J: Integer;
  Arc: array of TPointF;
begin
  Face := Darken(Pal.Facade[0], 0.95);
  Side := Darken(Face, 0.7);
  Win := Pal.Win;
  Steel := Darken(Pal.Facade[1], 0.8);

  { Empire State Building }
  X := 560; Base := CityBaseY;
  Box(B, X, Base - 210, X + 110, Base, Face);
  Box(B, X + 82, Base - 210, X + 110, Base, Side);
  Box(B, X + 14, Base - 300, X + 96, Base - 210, Face);
  Box(B, X + 74, Base - 300, X + 96, Base - 210, Side);
  Box(B, X + 28, Base - 360, X + 82, Base - 300, Face);
  Box(B, X + 66, Base - 360, X + 82, Base - 300, Side);
  Box(B, X + 38, Base - 398, X + 72, Base - 360, Face);
  Box(B, X + 46, Base - 430, X + 64, Base - 398, Face);
  Box(B, X + 51, Base - 470, X + 59, Base - 430, Steel);
  DLine(B, P(X + 55, 0).X, P(0, Base - 470).Y, P(X + 55, 0).X, P(0, Base - 520).Y, Steel, Max(0.7, S(1.6)));
  if FScene.FSeason = 2 then
  begin
    Box(B, X - 0.5, Base - 212.5, X + 110.5, Base - 209, Pal.Snow);
    Box(B, X + 13.5, Base - 302.5, X + 96.5, Base - 299, Pal.Snow);
    Box(B, X + 27.5, Base - 362.5, X + 82.5, Base - 359, Pal.Snow);
    Box(B, X + 37.5, Base - 400.5, X + 72.5, Base - 397, Pal.Snow);
    Box(B, X + 45.5, Base - 432, X + 64.5, Base - 429, Pal.Snow);
  end;
  // vertical window strips
  for I := 0 to 11 do
    DRect(B, X + 6 + I * 6.5, Base - 205, X + 9 + I * 6.5, Base - 4, Win);
  for I := 0 to 9 do
    DRect(B, X + 18 + I * 7, Base - 295, X + 21 + I * 7, Base - 214, Win);
  for I := 0 to 5 do
    DRect(B, X + 32 + I * 7.5, Base - 355, X + 35 + I * 7.5, Base - 304, Win);

  { Chrysler Building: stepped arches and a needle }
  X := 760;
  Box(B, X, Base - 250, X + 80, Base, Face);
  Box(B, X + 60, Base - 250, X + 80, Base, Side);
  for I := 0 to 9 do
    DRect(B, X + 6 + I * 7, Base - 244, X + 9 + I * 7, Base - 6, Win);
  for J := 0 to 4 do
  begin
    Wd := 66 - J * 12;
    Y := Base - 250 - J * 16;
    SetLength(Arc, 13);
    for I := 0 to 12 do
      Arc[I] := P(X + 40 + Cos(Pi - I * Pi / 12) * Wd / 2, Y - Sin(I * Pi / 12) * 20);
    Arc[0] := P(X + 40 - Wd / 2, Y);
    DPoly(B, Arc, Darken(Pal.Facade[1], 1.08));
    // triangular windows in the crown
    for I := 0 to 3 do
      DPoly(B, [P(X + 40 - Wd / 2 + 6 + I * (Wd - 12) / 3.4, Y - 4),
        P(X + 40 - Wd / 2 + 9 + I * (Wd - 12) / 3.4, Y - 11),
        P(X + 40 - Wd / 2 + 12 + I * (Wd - 12) / 3.4, Y - 4)], Win);
  end;
  DPoly(B, [P(X + 36, Base - 330), P(X + 40, Base - 410), P(X + 44, Base - 330)], Steel);

  { One World Trade Center: a tapering glass prism and a spire }
  X := 1150;
  DPoly(B, [P(X, Base), P(X + 120, Base), P(X + 120, Base - 70), P(X + 92, Base - 390),
    P(X + 28, Base - 390), P(X, Base - 70)], Pal.Glass);
  DPoly(B, [P(X + 60, Base - 70), P(X + 120, Base - 70), P(X + 92, Base - 390), P(X + 60, Base - 390)],
    Darken(Pal.Glass, 0.78));
  DPoly(B, [P(X, Base - 70), P(X + 60, Base - 390), P(X + 28, Base - 390)], Darken(Pal.Glass, 1.08));
  Box(B, X, Base - 70, X + 120, Base, Darken(Pal.Facade[1], 0.9));
  if FScene.FSeason = 2 then Box(B, X - 0.5, Base - 72.5, X + 120.5, Base - 69, Pal.Snow);
  for I := 0 to 40 do
    DLine(B, P(X + 4, 0).X, P(0, Base - 76 - I * 7.6).Y, P(X + 116 - I * 0.7, 0).X,
      P(0, Base - 76 - I * 7.6).Y, WithAlpha(Darken(Pal.Glass, 0.7), 120), Max(0.5, S(0.6)));
  Box(B, X + 50, Base - 400, X + 70, Base - 390, Steel);
  DLine(B, P(X + 60, 0).X, P(0, Base - 400).Y, P(X + 60, 0).X, P(0, Base - 495).Y, Steel, Max(0.7, S(1.6)));

  { a tower crane on a building going up }
  X := 990; Base := CityBaseY - 175;
  Box(B, X - 26, Base, X + 30, CityBaseY, Darken(Pal.Facade[2], 0.85));
  for I := 0 to 6 do  // unfinished floors: bare slabs
    Box(B, X - 26, Base - I * 0 + I * 25, X + 30, Base + I * 25 + 3, Darken(Pal.Stone, 0.6));
  for I := 0 to 11 do
  begin
    DLine(B, P(X - 4, 0).X, P(0, Base - I * 10).Y, P(X + 4, 0).X, P(0, Base - I * 10 - 10).Y,
      Darken(Pal.Stone, 0.6), Max(0.5, S(0.8)));
    DLine(B, P(X + 4, 0).X, P(0, Base - I * 10).Y, P(X - 4, 0).X, P(0, Base - I * 10 - 10).Y,
      Darken(Pal.Stone, 0.6), Max(0.5, S(0.8)));
  end;
  DLine(B, P(X - 4, 0).X, P(0, Base).Y, P(X - 4, 0).X, P(0, Base - 125).Y, Darken(Pal.Stone, 0.55), Max(0.6, S(1.2)));
  DLine(B, P(X + 4, 0).X, P(0, Base).Y, P(X + 4, 0).X, P(0, Base - 125).Y, Darken(Pal.Stone, 0.55), Max(0.6, S(1.2)));
  Box(B, X - 160, Base - 130, X + 50, Base - 123, Darken(Pal.Stone, 0.55));      // jib + counter jib
  Box(B, X + 30, Base - 136, X + 50, Base - 123, Darken(Pal.Stone, 0.4));        // counterweight
  DPoly(B, [P(X - 3, Base - 130), P(X, Base - 150), P(X + 3, Base - 130)], Darken(Pal.Stone, 0.55));
  DLine(B, P(X, 0).X, P(0, Base - 150).Y, P(X - 150, 0).X, P(0, Base - 130).Y, Darken(Pal.Stone, 0.55), Max(0.5, S(0.8)));
  DLine(B, P(X, 0).X, P(0, Base - 150).Y, P(X + 45, 0).X, P(0, Base - 130).Y, Darken(Pal.Stone, 0.55), Max(0.5, S(0.8)));

end;

{ The Statue of Liberty on her island, in the harbour in front of the city:
  star fort, pedestal, robe with folds, tablet, raised arm and torch. }
procedure TPainter.CutLiberty(B: TBGRABitmap; const Pal: TPal);
const
  K = LibertyK;
var
  X, Base: Single;
  I: Integer;
  Cu, CuD, CuL, Ped: TBGRAPixel;

  function L(DX, DY: Single): TPointF;
  begin
    Result := P(X + DX * K, Base - DY * K);
  end;

begin
  X := LibertyX; Base := LibertyBase;
  Cu := Pal.Liberty;
  CuD := Darken(Cu, 0.72);
  CuL := Darken(Cu, 1.15);
  Ped := Darken(Pal.Stone, 1.02);
  // island with trees and the star fort
  if FScene.FSeason = 2 then
  begin
    DEllipse(B, L(0, -3).X, L(0, -3).Y, S(95 * K), S(8 * K), Pal.Snow);
    for I := 0 to 6 do
      DEllipse(B, L(-80 + I * 26, 1).X, L(-80 + I * 26, 1).Y, S(9 * K), S(6 * K), Darken(Pal.Snow, 0.92 + 0.04 * (I mod 3)));
  end
  else
  begin
    DEllipse(B, L(0, -3).X, L(0, -3).Y, S(95 * K), S(8 * K), Darken(Pal.Tree, 0.85));
    for I := 0 to 6 do
      DEllipse(B, L(-80 + I * 26, 1).X, L(-80 + I * 26, 1).Y, S(9 * K), S(6 * K), Darken(Pal.Tree, 1 + 0.08 * (I mod 3)));
  end;
  DPoly(B, [L(-34, 0), L(34, 0), L(30, 8), L(-30, 8)], Darken(Pal.Stone, 0.8));
  // pedestal: base, shaft with a balcony, top
  DPoly(B, [L(-20, 8), L(20, 8), L(17, 22), L(-17, 22)], Darken(Ped, 0.92));
  DPoly(B, [L(-13, 22), L(13, 22), L(11, 50), L(-11, 50)], Ped);
  DPoly(B, [L(4, 22), L(13, 22), L(11, 50), L(4, 50)], Darken(Ped, 0.8));
  Box(B, X - 13 * K, Base - 54 * K, X + 13 * K, Base - 50 * K, Darken(Ped, 1.06));
  for I := 0 to 2 do
    Box(B, X + (-7 + I * 5) * K, Base - 44 * K, X + (-5 + I * 5) * K, Base - 30 * K, Darken(Ped, 0.6));
  // robe
  DPoly(B, [L(-8, 54), L(8, 54), L(7, 74), L(5, 92), L(-5, 92), L(-7, 74)], Cu);
  DPoly(B, [L(2, 54), L(8, 54), L(7, 74), L(5, 92), L(2, 92)], CuD);
  for I := 0 to 3 do
    DLine(B, L(-5 + I * 3, 56).X, L(0, 56).Y, L(-4 + I * 2.6, 0).X, L(0, 88).Y, CuD, Max(0.5, S(0.6 * K)));
  // left arm with the tablet
  DPoly(B, [L(-6, 86), L(-11, 80), L(-12, 70), L(-8, 70), L(-6, 80)], Cu);
  DPoly(B, [L(-15, 70), L(-8, 68), L(-7, 84), L(-14, 86)], CuL);
  // head with the crown rays
  DEllipse(B, L(0, 96).X, L(0, 96).Y, S(3.4 * K), S(4 * K), Cu);
  for I := 0 to 6 do
    DLine(B, L(0, 98).X, L(0, 98).Y, L(Cos(Pi * (0.1 + I * 0.8 / 6)) * 8, 0).X,
      L(0, 98 + Sin(Pi * (0.1 + I * 0.8 / 6)) * 7).Y, Cu, Max(0.5, S(0.9 * K)));
  // raised right arm and the torch
  DPoly(B, [L(3, 90), L(7, 88), L(10, 116), L(7, 117)], Cu);
  DPoly(B, [L(6, 117), L(11, 117), L(10, 121), L(7, 121)], CuD);
  DPoly(B, [L(6, 121), L(11, 121), L(9.5, 127), L(8.5, 129), L(7.5, 127)], Mix(Hex('#E8B048'), Pal.Liberty, 0.35));
end;

{ Suspension bridge: towers with twin pointed arches, main cables, suspenders,
  diagonal stays and the deck. }
procedure TPainter.CutBridge(B: TBGRABitmap; const Pal: TPal; Part: Integer);
var
  T, I, N: Integer;
  X, X0, X1, Y: Single;
  Line: array of TPointF;
  Stone, Dark, Cable: TBGRAPixel;
begin
  Stone := Pal.Stone;
  Dark := Darken(Stone, 0.72);
  Cable := Pal.Cable;
  X0 := FScene.FVisL - 80;
  X1 := FScene.FVisR + 80;
  if Part = 0 then
  begin
    // sheet 1: stays, suspenders and the main cables
    for T := 0 to 1 do
    begin
      if T = 0 then X := Tower1X + 35 else X := Tower2X + 35;
      for I := -9 to 9 do
        if I <> 0 then
          DLine(B, P(X, 0).X, P(0, TowerTopY + 30).Y, P(X + I * 26, 0).X, P(0, DeckY - 6).Y,
            Cable, Max(0.6, S(0.8)));
    end;
    X := Floor(X0 / 14) * 14;
    while X < X1 do
    begin
      if Abs(X - Tower1X - 35) > 40 then
        if Abs(X - Tower2X - 35) > 40 then
          DLine(B, P(X, 0).X, P(0, CableY(X)).Y, P(X, 0).X, P(0, DeckY - 6).Y, Cable, Max(0.6, S(0.8)));
      X := X + 14;
    end;
    N := Ceil((X1 - X0) / 6) + 1;
    SetLength(Line, N);
    for I := 0 to N - 1 do
    begin
      X := X0 + I * 6;
      Line[I] := P(X, CableY(X) - 3);
    end;
    DPolyLine(B, Line, Darken(Cable, 1.15), Max(0.8, S(1.8)));
    for I := 0 to N - 1 do
    begin
      X := X0 + I * 6;
      Line[I] := P(X, CableY(X));
    end;
    DPolyLine(B, Line, Cable, Max(1, S(3)));
    Exit;
  end;
  // sheet 2: deck and towers
  Box(B, X0, DeckY - 7, X1, DeckY + 9, Darken(Stone, 0.62));
  Box(B, X0, DeckY - 7, X1, DeckY - 4, Darken(Stone, 0.85));
  Box(B, X0, DeckY + 6, X1, DeckY + 9, Darken(Stone, 0.45));
  for T := 0 to 1 do
  begin
    if T = 0 then X := Tower1X else X := Tower2X;
    Box(B, X, TowerTopY, X + 70, RiverBotY - 10, Stone);
    Box(B, X + 52, TowerTopY, X + 70, RiverBotY - 10, Dark);
    for I := 0 to 1 do
    begin
      Y := TowerTopY + 46;
      DPoly(B, [P(X + 9 + I * 31, DeckY - 7), P(X + 9 + I * 31, Y + 24), P(X + 20 + I * 31, Y),
        P(X + 31 + I * 31, Y + 24), P(X + 31 + I * 31, DeckY - 7)], Mix(Darken(Stone, 0.42), Pal.Water2, 0.3));
    end;
    Box(B, X - 4, TowerTopY - 6, X + 74, TowerTopY + 4, Darken(Stone, 1.1));
    Box(B, X + 3, RiverBotY - 22, X + 67, RiverBotY - 8, Dark);
    if FScene.FSeason = 2 then Box(B, X - 4.5, TowerTopY - 9, X + 74.5, TowerTopY - 5.5, Pal.Snow);
  end;
  if FScene.FSeason = 2 then Box(B, X0, DeckY - 9.5, X1, DeckY - 6.5, Pal.Snow);
end;

{ Railing, sidewalks, road markings, crosswalk, trees and lamp posts. }
procedure TPainter.CutStreet(B: TBGRABitmap; const Pal: TPal; Part: Integer);
var
  X, X0, X1: Single;
  I: Integer;
  Pole, Line, Curb: TBGRAPixel;
begin
  X0 := FScene.FVisL - 40;
  X1 := FScene.FVisR + 40;
  Pole := Darken(Pal.Road, 0.6);
  Curb := Darken(Pal.Walk, 0.75);
  case Part of
    0: begin  // the road (base of the street, no shadow of its own)
         Box(B, X0, RoadTopY - 4, X1, RoadBotY + 6, Pal.Road);
         Box(B, X0, RoadMidY + 3, X1, RoadBotY + 6, Darken(Pal.Road, 1.06));
         X := Floor(X0 / 60) * 60;
         while X < X1 do
         begin
           if Abs(X - SignalX + 50) > 70 then
           begin
             Box(B, X, RoadMidY - 2.2, X + 30, RoadMidY - 0.6, Hex('#E8C33A'));
             Box(B, X, RoadMidY + 0.6, X + 30, RoadMidY + 2.2, Hex('#E8C33A'));
           end;
           X := X + 60;
         end;
         for I := 0 to 7 do
           Box(B, SignalX - 108 + I * 9, RoadTopY + 4, SignalX - 103 + I * 9, RoadBotY - 4,
             Mix(Pal.Walk, Hex('#FFFFFF'), 0.5));
         Line := Mix(Pal.Walk, Hex('#FFFFFF'), 0.55);
         Box(B, SignalX - 116, RoadTopY + 4, SignalX - 113, RoadMidY - 3, Line);
         Box(B, SignalX - 4, RoadMidY + 3, SignalX - 1, RoadBotY - 4, Line);
         if FScene.FSeason = 1 then  // puddles mirroring the sky
           for I := 0 to 40 do
           begin
             X := Floor(X0 / 400) * 400 + I * 97 + 60 * Hash01(I * 7);
             if X > X1 then Break;
             DEllipse(B, P(X, 0).X, P(0, RoadTopY + 8 + Hash01(I * 3) * 80).Y, S(14 + 20 * Hash01(I * 5)),
               S(2.2 + 2 * Hash01(I * 11)), Mix(Pal.Road, Pal.SkyBot, 0.35));
           end;
         if FScene.FSeason = 2 then  // slush along both curbs
         begin
           Box(B, X0, RoadTopY - 4, X1, RoadTopY + 3, Mix(Pal.Snow, Pal.Road, 0.35));
           Box(B, X0, RoadBotY - 4, X1, RoadBotY + 6, Mix(Pal.Snow, Pal.Road, 0.35));
         end;
       end;
    1: begin  // far side sheet: river wall, railing, sidewalk, trees, lamps, signal
         Box(B, X0, RiverBotY - 6, X1, WalkTopY, Darken(Pal.Walk, 0.6));
         DLine(B, P(X0, 0).X, P(0, RiverBotY - 18).Y, P(X1, 0).X, P(0, RiverBotY - 18).Y, Pole, Max(0.8, S(1.8)));
         X := Floor(X0 / 16) * 16;
         while X < X1 do
         begin
           DLine(B, P(X, 0).X, P(0, RiverBotY - 18).Y, P(X, 0).X, P(0, RiverBotY - 6).Y, Pole, Max(0.6, S(1.2)));
           X := X + 16;
         end;
         Box(B, X0, WalkTopY, X1, RoadTopY, Pal.Walk);
         Box(B, X0, RoadTopY - 3, X1, RoadTopY, Curb);
         for I := 0 to High(FScene.FLamps) do
         begin
           X := FScene.FLamps[I] + 105;
           DLine(B, P(X, 0).X, P(0, WalkTopY + 18).Y, P(X, 0).X, P(0, WalkTopY - 18).Y, Darken(Pal.Road, 0.7), Max(0.8, S(2.6)));
           if FScene.FSeason = 2 then
           begin  // bare branches with snow on them
             DLine(B, P(X, 0).X, P(0, WalkTopY - 16).Y, P(X - 16, 0).X, P(0, WalkTopY - 40).Y, Pal.Tree, Max(0.6, S(1.6)));
             DLine(B, P(X, 0).X, P(0, WalkTopY - 14).Y, P(X + 15, 0).X, P(0, WalkTopY - 42).Y, Pal.Tree, Max(0.6, S(1.6)));
             DLine(B, P(X, 0).X, P(0, WalkTopY - 18).Y, P(X + 2, 0).X, P(0, WalkTopY - 50).Y, Pal.Tree, Max(0.6, S(1.8)));
             DLine(B, P(X - 9, 0).X, P(0, WalkTopY - 29).Y, P(X - 20, 0).X, P(0, WalkTopY - 32).Y, Pal.Tree, Max(0.5, S(1.1)));
             DLine(B, P(X + 8, 0).X, P(0, WalkTopY - 28).Y, P(X + 21, 0).X, P(0, WalkTopY - 30).Y, Pal.Tree, Max(0.5, S(1.1)));
             DEllipse(B, P(X - 16, WalkTopY - 41).X, P(0, WalkTopY - 41).Y, S(4), S(2), Pal.Snow);
             DEllipse(B, P(X + 15, WalkTopY - 43).X, P(0, WalkTopY - 43).Y, S(4), S(2), Pal.Snow);
             DEllipse(B, P(X + 2, WalkTopY - 51).X, P(0, WalkTopY - 51).Y, S(3.5), S(2), Pal.Snow);
             DEllipse(B, P(X, WalkTopY + 18).X, P(0, WalkTopY + 18).Y, S(9), S(2.5), Pal.Snow);
           end
           else
           begin
             DEllipse(B, P(X, WalkTopY - 30).X, P(X, WalkTopY - 30).Y, S(21), S(18), Pal.Tree);
             DEllipse(B, P(X - 6, WalkTopY - 36).X, P(X - 6, WalkTopY - 36).Y, S(11), S(9), Darken(Pal.Tree, 1.2));
           end;
         end;
         if FScene.FSeason = 2 then  // snow on the railing
           DLine(B, P(X0, 0).X, P(0, RiverBotY - 19.5).Y, P(X1, 0).X, P(0, RiverBotY - 19.5).Y, Pal.Snow, Max(1, S(2.6)));
         for I := 0 to High(FScene.FLamps) do
         begin
           X := FScene.FLamps[I];
           DLine(B, P(X, 0).X, P(0, WalkTopY + 22).Y, P(X, 0).X, P(0, WalkTopY - 112).Y, Pole, Max(0.8, S(2.8)));
           DPolyLine(B, [P(X, WalkTopY - 112), P(X + 6, WalkTopY - 120), P(X + 22, WalkTopY - 121)], Pole, Max(0.7, S(2.2)));
           Box(B, X + 15, WalkTopY - 124, X + 33, WalkTopY - 118, Pole);
           if FScene.FSeason = 2 then Box(B, X + 14.5, WalkTopY - 126.5, X + 33.5, WalkTopY - 123.5, Pal.Snow);
         end;
         DLine(B, P(SignalX, 0).X, P(0, WalkTopY + 22).Y, P(SignalX, 0).X, P(0, SignalTop).Y, Pole, Max(1, S(3)));
         Box(B, SignalX - 7, SignalTop, SignalX + 7, SignalTop + 42, Darken(Pole, 0.6));
         Box(B, SignalX - 9, SignalTop - 2, SignalX + 9, SignalTop + 1, Darken(Pole, 0.5));
       end;
  else
    begin  // near sidewalk sheet
      Box(B, X0, RoadBotY, X1, DesignH + 20, Pal.Walk);
      Box(B, X0, RoadBotY, X1, RoadBotY + 4, Curb);
      X := Floor(X0 / 46) * 46;
      while X < X1 do
      begin
        DLine(B, P(X, 0).X, P(0, RoadBotY + 4).Y, P(X, 0).X, P(0, DesignH + 10).Y, Darken(Pal.Walk, 0.85), Max(0.5, S(0.8)));
        X := X + 46;
      end;
    end;
  end;
end;

{ ---------- dynamic parts ---------- }

procedure TPainter.DrawStars(Dest: TBGRABitmap);
var
  I, A: Integer;
  N: Single;
  Q: TPointF;
begin
  N := FScene.Night;
  if N < 0.05 then Exit;
  if not RowsHit(0, 560) then Exit;
  for I := 0 to High(FScene.FStars) do
    with FScene.FStars[I] do
    begin
      Q := P(X, Y);
      if (Q.Y < -3) or (Q.Y > FTargetH + 3) then Continue;
      A := Round(255 * N * (0.45 + 0.55 * Sin(FScene.FTime * (1.3 + Phase) + Phase * 7)));
      if A > 8 then DEllipse(Dest, Q.X, Q.Y, S(R), S(R), BGRA(255, 250, 235, A));
    end;
end;

procedure TPainter.DrawClouds(Dest: TBGRABitmap);
var
  I, A: Integer;
  Q: TPointF;
begin
  if not RowsHit(30, 420) then Exit;
  A := Round(255 * FScene.FBlend);
  for I := 0 to High(FScene.FClouds) do
    with FScene.FClouds[I] do
    begin
      Q := P(MinX - 12 + OX, MinY - 12);
      if FSvg <> nil then
        FSvg.Raw(Format('<g transform="translate(%s,%s)">', [FSvg.N(Round(Q.X)), FSvg.N(Round(Q.Y))]) +
          LineEnding + Svg[FScene.CurrentMode] + '</g>');
      if not FRaster then Continue;
      BlendBitmap(Dest, Round(Q.X), Round(Q.Y), Sprite[FScene.FFrom], 255 - IfThen(FScene.FFrom = FScene.FTo, 0, 0));
      if (FScene.FFrom <> FScene.FTo) and (A > 0) then
        BlendBitmap(Dest, Round(Q.X), Round(Q.Y), Sprite[FScene.FTo], A);
    end;
end;

{ The crane trolley runs along the jib and the hook load swings below it. }
procedure TPainter.DrawCraneLoad(Dest: TBGRABitmap);
var
  X, Base, Tx, Hy, Sw, K: Single;
  Steel: TBGRAPixel;
  Q, R: TPointF;
begin
  if FPart <> 0 then Exit;
  X := 990; Base := CityBaseY - 175;
  if not RowsHit(Base - 140, Base + 10) then Exit;
  K := FScene.Shade;
  Steel := Darken(BGRA(90, 86, 82), K);
  Tx := X - 40 - 100 * (0.5 + 0.5 * Sin(FScene.FTime * 0.25));
  Hy := Base - 70 + 40 * Sin(FScene.FTime * 0.37);
  Sw := 4 * Sin(FScene.FTime * 1.7);
  Q := P(Tx, Base - 123);
  R := P(Tx + Sw, Hy);
  Box(Dest, Tx - 5, Base - 124, Tx + 5, Base - 119, Steel);
  DLine(Dest, Q.X, Q.Y, R.X, R.Y, Steel, Max(0.5, S(0.8)));
  Box(Dest, Tx + Sw - 9, Hy, Tx + Sw + 9, Hy + 6, Darken(BGRA(200, 120, 40), K));
end;

{ Lit windows that switch on and off now and then. }
procedure TPainter.DrawFlicker(Dest: TBGRABitmap);
var
  I: Integer;
  N: Single;
begin
  N := FScene.Night;
  if N < 0.05 then Exit;
  for I := 0 to High(FScene.FFlicker) do
    with FScene.FFlicker[I] do
    begin
      if not RowsHit(Y, Y + H) then Continue;
      if Sin(FScene.FTime * Rate + Phase) > 0.2 then
        DRect(Dest, X, Y, X + W, Y + H, WithAlpha(C, Round(255 * N)))
      else
        DRect(Dest, X, Y, X + W, Y + H, WithAlpha(FScene.FPal[2].Win, Round(255 * N)));
    end;
end;

{ Floodlights and beacons: Empire State top changing colour, Chrysler crown,
  One WTC spire beacon, red roof beacons, the crane, the torch of Liberty. }
procedure TPainter.DrawLandmarkLights(Dest: TBGRABitmap);
var
  N, Tm, Ph, K: Single;
  I, A: Integer;
  C, C1, C2: TBGRAPixel;
  X, Base, Y, Wd: Single;
  Cols: array[0..2] of TBGRAPixel;
begin
  N := FScene.Night;
  if N < 0.05 then Exit;
  Tm := FScene.FTime;
  A := Round(255 * N);
  if RowsHit(0, CityBaseY) then
  begin
    // Empire State: red -> white -> blue, slowly
    Cols[0] := Hex('#E8303A'); Cols[1] := Hex('#F4F4FF'); Cols[2] := Hex('#3A6BFF');
    Ph := Frac(Tm / 12) * 3;
    I := Trunc(Ph);
    K := Ph - I;
    K := K * K * (3 - 2 * K);
    C := Mix(Cols[I mod 3], Cols[(I + 1) mod 3], K);
    X := 560; Base := CityBaseY;
    Box(Dest, X + 38, Base - 398, X + 72, Base - 360, WithAlpha(C, Round(A * 0.85)));
    Box(Dest, X + 46, Base - 430, X + 64, Base - 398, WithAlpha(C, Round(A * 0.9)));
    Box(Dest, X + 28, Base - 360, X + 82, Base - 352, WithAlpha(C, Round(A * 0.6)));
    Glow(Dest, X + 55, Base - 410, 60, WithAlpha(C, Round(A * 0.35)));
    Glow(Dest, X + 55, Base - 520, 6 + 2 * Sin(Tm * 4), WithAlpha(Hex('#FF2A1A'), A));
    // Chrysler: the crown arcs light up white
    X := 760;
    for I := 0 to 4 do
    begin
      Wd := 66 - I * 12;
      Y := Base - 250 - I * 16;
      DPolyLine(Dest, [P(X + 40 - Wd / 2, Y - 2), P(X + 40 - Wd / 4, Y - 16), P(X + 40, Y - 20),
        P(X + 40 + Wd / 4, Y - 16), P(X + 40 + Wd / 2, Y - 2)],
        WithAlpha(Hex('#FFF1D0'), Round(A * (0.7 + 0.3 * Sin(Tm * 2 + I)))), Max(0.8, S(1.6)));
    end;
    Glow(Dest, X + 40, Base - 300, 50, WithAlpha(Hex('#FFF1D0'), Round(A * 0.25)));
    // One WTC: lit edge and a pulsing spire beacon
    X := 1150;
    DLine(Dest, P(X + 60, 0).X, P(0, Base - 72).Y, P(X + 60, 0).X, P(0, Base - 390).Y,
      WithAlpha(Hex('#CFE6FF'), Round(A * 0.55)), Max(0.6, S(1.2)));
    K := 0.5 + 0.5 * Sin(Tm * 2.2);
    Glow(Dest, X + 60, Base - 495, 10 + 14 * K, WithAlpha(Hex('#FFFFFF'), Round(A * (0.5 + 0.5 * K))));
    // red roof beacons blink
    for I := 0 to High(FScene.FBeacons) do
      if Frac(Tm / 1.6 + I * 0.137) < 0.28 then
        Glow(Dest, FScene.FBeacons[I].X, FScene.FBeacons[I].Y, 7, WithAlpha(Hex('#FF2A1A'), A));
    // crane: aviation lights and a work floodlight
    X := 990; Base := CityBaseY - 175;
    if Frac(Tm / 1.2) < 0.5 then
    begin
      Glow(Dest, X - 160, Base - 130, 6, WithAlpha(Hex('#FF2A1A'), A));
      Glow(Dest, X, Base - 150, 6, WithAlpha(Hex('#FF2A1A'), A));
    end;
    C1 := WithAlpha(Hex('#FFF0B0'), Round(A * 0.45));
    C2 := WithAlpha(Hex('#FFF0B0'), 0);
    DPolyG(Dest, [P(X - 30, Base - 120), P(X - 18, Base - 120), P(X + 20, Base), P(X - 70, Base)],
      MakeGrad(C1, C2, False, P(0, Base - 120), P(0, Base)));
    Glow(Dest, X - 24, Base - 120, 7, WithAlpha(Hex('#FFF6DA'), A));
    // torch of Liberty and a soft floodlight on her
    X := LibertyX; Base := LibertyBase;
    Glow(Dest, X + 8.5 * LibertyK, Base - 127 * LibertyK, 14 + 3 * Sin(Tm * 9) + 2 * Sin(Tm * 13),
      WithAlpha(Hex('#FFC64A'), A));
    Glow(Dest, X, Base - 70 * LibertyK, 60, WithAlpha(Hex('#9FE0C8'), Round(A * 0.3)));
    // bridge tower tops
    Glow(Dest, Tower1X + 35, TowerTopY - 8, 6, WithAlpha(Hex('#FF2A1A'), Round(A * (0.6 + 0.4 * Sin(Tm * 2)))));
    Glow(Dest, Tower2X + 35, TowerTopY - 8, 6, WithAlpha(Hex('#FF2A1A'), Round(A * (0.6 + 0.4 * Sin(Tm * 2 + 1)))));
  end;
end;

{ Waves: short bright strokes drifting across the water. }
{ The river as 4 paper wave strips, each with its wavy top edge rolling across
  (neighbouring strips run in opposite directions), a light crest line and a
  thin hard shadow on the strip behind it. }
procedure TPainter.DrawWaves(Dest: TBGRABitmap);
const
  Strips = 4;
var
  Sc: TCityScene;
  K, I, N: Integer;
  X, X0, X1, Y, Base, Amp, T: Single;
  Edge: array of TPointF;
  W1, W2, C, Crest: TBGRAPixel;
begin
  Sc := FScene;
  if not RowsHit(CityBaseY, RiverBotY + 4) then Exit;
  W1 := Mix(Sc.FPal[Sc.FFrom].Water1, Sc.FPal[Sc.FTo].Water1, Sc.FBlend);
  W2 := Mix(Sc.FPal[Sc.FFrom].Water2, Sc.FPal[Sc.FTo].Water2, Sc.FBlend);
  X0 := Sc.FVisL - 30;
  X1 := Sc.FVisR + 30;
  N := Ceil((X1 - X0) / 10) + 1;
  SetLength(Edge, N);
  for K := 0 to Strips - 1 do
  begin
    Base := CityBaseY + 16 + K * 30;
    if not RowsHit(Base - 12, RiverBotY + 4) then Continue;
    Amp := 2.6 + K * 1.3;
    T := Sc.FTime * (0.7 + 0.3 * K);
    if Odd(K) then T := -T;
    for I := 0 to N - 1 do
    begin
      X := X0 + I * 10;
      Y := Base + Amp * Sin(X * (0.045 - K * 0.007) + T + K * 1.3) +
        Amp * 0.4 * Sin(X * 0.11 - T * 1.7 + K);
      Edge[I] := P(X, Y);
    end;
    // the strip only has to reach below the lowest trough of the next strip
    if K = Strips - 1 then Y := RiverBotY + 2 else Y := Base + 30 + 2.6 + (K + 1) * 1.3 * 1.4 + 3;
    C := Mix(W1, W2, 0.18 + 0.24 * K);
    Crest := Mix(C, BGRA(255, 255, 255), 0.28 * (1 - Sc.Night * 0.75));
    EdgeFill(Dest, Edge, S(1.5), -S(3.5), S(3.5), 0, BGRA(0, 0, 20, 45));  // paper edge shadow
    EdgeFill(Dest, Edge, 0, 0, 0, P(0, Y).Y, C);                           // the strip
    EdgeFill(Dest, Edge, 0, 0, Max(0.8, S(1.4)), 0, Crest);                 // light crest
    if Sc.FSeason = 2 then  // ice floes riding on the strip
      for I := 0 to 4 do
      begin
        X := Sc.FVisL - 40 + PFrac(Hash01(K * 9 + I) + Sc.FTime * 0.006 * (1 + K * 0.3) * (1 - 2 * Ord(Odd(K)))) *
          (Sc.FVisR - Sc.FVisL + 80);
        Y := Base + Amp * Sin(X * (0.045 - K * 0.007) + T + K * 1.3) + 3;
        DEllipse(Dest, P(X + 1.5, Y + 1.5).X, P(0, Y + 1.5).Y, S(9 + 9 * Hash01(I * 3 + K)), S(2.6), BGRA(0, 0, 20, 50));
        DEllipse(Dest, P(X, Y).X, P(0, Y).Y, S(9 + 9 * Hash01(I * 3 + K)), S(2.4),
          Mix(Hex('#F2F6FA'), C, 0.25 + 0.4 * Sc.Night));
      end;
  end;
end;

{ Light reflections: shimmering columns under the lit city and the bridge at
  night, a glitter path under the sun by day. }
procedure TPainter.DrawReflections(Dest: TBGRABitmap);
var
  I, J, A: Integer;
  N, Y, Wob, Len, Day, SunX: Single;
  Q: TPointF;
  C: TBGRAPixel;
begin
  if not RowsHit(CityBaseY, RiverBotY) then Exit;
  N := FScene.Night;
  if N > 0.05 then
    for I := 0 to High(FScene.FRefl) do
      with FScene.FRefl[I] do
      begin
        if (X < FScene.FVisL - 20) or (X > FScene.FVisR + 20) then Continue;
        J := 0;
        Y := CityBaseY + 4;
        while Y < RiverBotY - 6 do
        begin
          Inc(J);
          Wob := Sin(FScene.FTime * 1.6 + Y * 0.35 + I) * 3;
          A := Round(255 * N * Strength * (0.45 + 0.55 * Sin(FScene.FTime * 3.1 + J * 1.7 + I * 0.9)) *
            (1 - 0.6 * (Y - CityBaseY) / (RiverBotY - CityBaseY)));
          Len := 3 + 5 * Hash01(I * 31 + J);
          if (A > 6) and not ((Y > DeckY - 8) and (Y < DeckY + 10)) then
          begin
            HDash(Dest, X + Wob - Len / 2, Y, Len, 1.4, WithAlpha(C, A));
          end;
          Y := Y + 5;
        end;
      end;
  // sun glitter
  Day := 1 - N;
  if Day > 0.05 then
  begin
    SunX := FScene.FPal[FScene.CurrentMode].SunX;
    C := BGRA(255, 246, 220);
    for J := 0 to 40 do
    begin
      Y := CityBaseY + 4 + J * 3.3;
      if (Y > DeckY - 8) and (Y < DeckY + 10) then Continue;
      Wob := Sin(FScene.FTime * 2 + J * 1.3) * (6 + J * 0.8);
      Len := 6 + 12 * Hash01(J + Round(FScene.FTime * 4));
      A := Round(200 * Day * (0.3 + 0.7 * Abs(Sin(FScene.FTime * 4 + J))));
      HDash(Dest, SunX + Wob - Len / 2, Y, Len, 1.2, WithAlpha(C, A));
    end;
  end;
end;

{ Cars crossing the bridge (white headlights one way, red taillights the
  other at night) and a subway train with lit windows. }
procedure TPainter.DrawBridgeTraffic(Dest: TBGRABitmap);
var
  I, K: Integer;
  N, Sh, Y, Tx: Single;
  Body: TBGRAPixel;
begin
  if not RowsHit(DeckY - 16, DeckY + 10) then Exit;
  N := FScene.Night;
  Sh := FScene.Shade;
  for I := 0 to High(FScene.FBridgeCars) do
    with FScene.FBridgeCars[I] do
    begin
      if (X < FScene.FVisL - 20) or (X > FScene.FVisR + 20) then Continue;
      if Dir > 0 then Y := DeckY - 4 else Y := DeckY + 1;
      if not RowsHit(Y - 10, Y + 5) then Continue;
      if FPart = 0 then
      begin
        Body := Darken(Color, Sh);
        Box(Dest, X - 7, Y - 5, X + 7, Y, Body);
        Box(Dest, X - 4, Y - 8, X + 4, Y - 5, Darken(Body, 0.85));
      end
      else if N > 0.05 then
      begin
        Glow(Dest, X + Dir * 8, Y - 2.5, 7, WithAlpha(Hex('#FFF3D0'), Round(255 * N)));
        Glow(Dest, X + Dir * 16, Y - 1, 12, WithAlpha(Hex('#FFE8B0'), Round(70 * N)));
        Glow(Dest, X - Dir * 8, Y - 2.5, 4.5, WithAlpha(Hex('#FF2A1A'), Round(230 * N)));
      end;
    end;
  // subway train
  Tx := FScene.FTrainX;
  if Tx > FScene.FVisL - 300 then
    for K := 0 to 5 do
    begin
      Y := DeckY - 5;
      if FPart = 0 then
      begin
        Box(Dest, Tx - K * 44 - 42, Y - 13, Tx - K * 44, Y, Darken(Hex('#B8BEC6'), Sh));
        Box(Dest, Tx - K * 44 - 42, Y - 4, Tx - K * 44, Y - 2, Darken(Hex('#2F6FD0'), Sh));
        for I := 0 to 4 do
          Box(Dest, Tx - K * 44 - 38 + I * 8, Y - 11, Tx - K * 44 - 33 + I * 8, Y - 6,
            Mix(Darken(Hex('#3A4A5C'), Sh), Hex('#FFF1C0'), N));
      end
      else if N > 0.05 then
      begin
        // the lit coach spills light around it, the front lamp shines ahead
        Glow(Dest, Tx - K * 44 - 21, Y - 8, 26, WithAlpha(Hex('#FFE7A8'), Round(55 * N)));
        if K = 0 then
        begin
          Glow(Dest, Tx + 1, Y - 6, 8, WithAlpha(Hex('#FFFFFF'), Round(255 * N)));
          Glow(Dest, Tx + 24, Y - 4, 22, WithAlpha(Hex('#FFF0C8'), Round(90 * N)));
        end;
        if K = 5 then
          Glow(Dest, Tx - 5 * 44 - 42, Y - 6, 5, WithAlpha(Hex('#FF2A1A'), Round(230 * N)));
      end;
    end;
end;

{ Ferry, tug and sailboat with reflections; cabin and navigation lights at night. }
procedure TPainter.DrawBoats(Dest: TBGRABitmap);
var
  I, K: Integer;
  N, Sh, X, Y, Sz, Bob: Single;
  Hull, Cab, Win: TBGRAPixel;

  { a light on the boat and its shimmering streak on the water below }
  procedure Lamp(LX, LY, R: Single; C: TBGRAPixel; Strength: Single);
  var
    J: Integer;
    WY, Wob, Len: Single;
  begin
    Glow(Dest, LX, LY, R, WithAlpha(C, Round(255 * Strength * N)));
    WY := Y + 4 * Sz;
    for J := 1 to 7 do
    begin
      Wob := Sin(FScene.FTime * 3 + J * 1.9 + LX * 0.1) * 2.5;
      Len := 3 + 4 * Hash01(J * 13 + Round(LX));
      HDash(Dest, LX + Wob - Len / 2, WY + J * 3.4, Len, 1.4,
        WithAlpha(C, Round(200 * Strength * N * (1 - J / 8) * (0.5 + 0.5 * Sin(FScene.FTime * 5 + J)))));
    end;
  end;

begin
  if not RowsHit(DeckY + 8, RiverBotY + 30) then Exit;
  N := FScene.Night;
  Sh := FScene.Shade;
  Win := Mix(Darken(Hex('#2A3240'), Sh), Hex('#FFE7A8'), N);
  for I := 0 to High(FScene.FBoats) do
  begin
    X := FScene.FBoats[I].X;
    Sz := FScene.FBoats[I].Size;
    Bob := Sin(FScene.FTime * 1.4 + I * 2) * 1.2;
    Y := FScene.FBoats[I].Y + Bob;
    if (X < FScene.FVisL - 120) or (X > FScene.FVisR + 120) then Continue;
    if not RowsHit(Y - 50 * Sz, Y + 30 * Sz) then Continue;
    if (FPart = 1) and (N < 0.05) then Continue;
    case FScene.FBoats[I].Kind of
      0: if FPart = 0 then
         begin  // Staten Island ferry: orange hull, white decks
           Hull := Darken(Hex('#E8792A'), Sh);
           Cab := Darken(Hex('#EDEDE6'), Sh);
           DPoly(Dest, [P(X - 60 * Sz, Y - 8 * Sz), P(X + 60 * Sz, Y - 8 * Sz), P(X + 52 * Sz, Y + 2 * Sz),
             P(X - 52 * Sz, Y + 2 * Sz)], Hull);
           Box(Dest, X - 48 * Sz, Y - 16 * Sz, X + 48 * Sz, Y - 8 * Sz, Cab);
           Box(Dest, X - 34 * Sz, Y - 23 * Sz, X + 34 * Sz, Y - 16 * Sz, Cab);
           Box(Dest, X - 6 * Sz, Y - 29 * Sz, X + 6 * Sz, Y - 23 * Sz, Darken(Cab, 0.85));
           for K := 0 to 11 do
             Box(Dest, X - 44 * Sz + K * 7.5 * Sz, Y - 14 * Sz, X - 40 * Sz + K * 7.5 * Sz, Y - 10 * Sz, Win);
           for K := 0 to 7 do
             Box(Dest, X - 30 * Sz + K * 8 * Sz, Y - 21 * Sz, X - 26 * Sz + K * 8 * Sz, Y - 18 * Sz, Win);
         end
         else
         begin
           Glow(Dest, X, Y - 15 * Sz, 58 * Sz, WithAlpha(Hex('#FFE7A8'), Round(60 * N)));
           for K := 0 to 5 do
             Lamp(X - 40 * Sz + K * 16 * Sz, Y - 12 * Sz, 7, Hex('#FFE7A8'), 0.55);
           Lamp(X - 60 * Sz, Y - 8 * Sz, 6, Hex('#FF2A1A'), 1);
           Lamp(X + 60 * Sz, Y - 8 * Sz, 6, Hex('#2AFF6A'), 1);
           Glow(Dest, X, Y - 31 * Sz, 6, WithAlpha(Hex('#FFFFFF'), Round(255 * N)));
         end;
      1: if FPart = 0 then
         begin  // tug pushing a barge
           Hull := Darken(Hex('#2E3A4A'), Sh);
           Box(Dest, X - 70 * Sz, Y - 6 * Sz, X - 14 * Sz, Y + 2 * Sz, Darken(Hex('#5A4A3A'), Sh));
           DPoly(Dest, [P(X - 14 * Sz, Y - 7 * Sz), P(X + 22 * Sz, Y - 7 * Sz), P(X + 18 * Sz, Y + 2 * Sz),
             P(X - 14 * Sz, Y + 2 * Sz)], Hull);
           Box(Dest, X - 4 * Sz, Y - 17 * Sz, X + 12 * Sz, Y - 7 * Sz, Darken(Hex('#C83A2A'), Sh));
           Box(Dest, X - 1 * Sz, Y - 15 * Sz, X + 9 * Sz, Y - 11 * Sz, Win);
         end
         else
         begin
           Lamp(X + 4 * Sz, Y - 13 * Sz, 9, Hex('#FFE7A8'), 0.6);
           Glow(Dest, X + 4 * Sz, Y - 19 * Sz, 5, WithAlpha(Hex('#FFFFFF'), Round(255 * N)));
           Lamp(X - 70 * Sz, Y - 6 * Sz, 5, Hex('#FFD040'), 0.9);
         end;
    else
      if FPart = 0 then
      begin  // sailboat
        Hull := Darken(Hex('#F2F2EE'), Sh);
        DPoly(Dest, [P(X - 18 * Sz, Y - 4 * Sz), P(X + 20 * Sz, Y - 4 * Sz), P(X + 15 * Sz, Y + 2 * Sz),
          P(X - 14 * Sz, Y + 2 * Sz)], Hull);
        DLine(Dest, P(X, 0).X, P(0, Y - 4 * Sz).Y, P(X, 0).X, P(0, Y - 44 * Sz).Y, Darken(Hex('#606060'), Sh), Max(0.6, S(1.2)));
        DPoly(Dest, [P(X - 1, Y - 42 * Sz), P(X - 1, Y - 6 * Sz), P(X - 20 * Sz, Y - 6 * Sz)],
          Darken(Hex('#FAFAF4'), Sh));
        DPoly(Dest, [P(X + 1, Y - 38 * Sz), P(X + 1, Y - 6 * Sz), P(X + 15 * Sz, Y - 6 * Sz)],
          Darken(Hex('#E8E4D8'), Sh));
      end
      else
        Lamp(X, Y - 45 * Sz, 5, Hex('#FFFFFF'), 1);
    end;
  end;
end;

procedure TPainter.DrawSignal(Dest: TBGRABitmap);
var
  St, I: Integer;
  On: array[0..2] of TBGRAPixel;
  Y: Single;
begin
  if not RowsHit(SignalTop - 20, SignalTop + 60) then Exit;
  St := FScene.SignalState;
  On[0] := Hex('#FF2A1A'); On[1] := Hex('#FFC21A'); On[2] := Hex('#2AE06A');
  for I := 0 to 2 do
  begin
    Y := SignalTop + 7 + I * 13;
    if ((I = 0) and (St = 2)) or ((I = 1) and (St = 1)) or ((I = 2) and (St = 0)) then
    begin
      DEllipse(Dest, P(SignalX, Y).X, P(SignalX, Y).Y, S(4.5), S(4.5), On[I]);
      Glow(Dest, SignalX, Y, 16, WithAlpha(On[I], Round(70 + 140 * FScene.Night)));
    end
    else
      DEllipse(Dest, P(SignalX, Y).X, P(SignalX, Y).Y, S(4.5), S(4.5), Darken(On[I], 0.25));
  end;
end;

{ One road vehicle, side view, facing its direction of travel. At night it has
  a headlight beam on the road, a lit front lamp and red taillights. }
{ One road vehicle, side view, facing its direction of travel.
  Paper part: body, windows, wheels. Light part (drawn after the shadow): at night
  a headlight beam with a pool on the road, a bright lamp; red tail lights with
  a glow on the asphalt; brake lights flare up whenever the car slows or stands
  (by day too); the taxi sign and the lit bus windows glow. }
procedure TPainter.DrawCar(Dest: TBGRABitmap; const C: TCar);
var
  Dir, X, Y, L, H, N, Sh, F, R0, I, TailK: Single;
  K: Integer;
  Body, Glass, Dark: TBGRAPixel;

  function Q(DX, DY: Single): TPointF;  // DX from the rear, DY up from the road
  begin
    Result := P(X + Dir * (DX - L / 2), Y - DY);
  end;

  procedure Streak(LX: Single; LC: TBGRAPixel; Strength: Single);
  var
    J: Integer;
    Wob, Len: Single;
  begin
    for J := 1 to 8 do
    begin
      Wob := Sin(FScene.FTime * 4 + J * 1.7 + LX * 0.13) * 1.6;
      Len := 3 + 4 * Hash01(J * 17 + Round(LX * 3));
      HDash(Dest, LX + Wob - Len / 2, Y + 1 + J * 2.6, Len, 1.2,
        WithAlpha(LC, Round(170 * Strength * (1 - J / 9))));
    end;
  end;

begin
  if C.Lane = 0 then Dir := -1 else Dir := 1;
  if C.Lane = 0 then Y := RoadMidY - 6 else Y := RoadBotY - 6;
  X := C.X;
  L := C.Len;
  H := C.H;
  N := FScene.Night;
  Sh := FScene.Shade;
  if FPart = 0 then
  begin
    if not RowsHit(Y - H - 8, Y + 10) then Exit;
    Body := Darken(C.Color, Sh);
    Dark := Darken(Body, 0.7);
    Glass := Mix(Darken(Hex('#6F8BA6'), Sh), Hex('#1A2230'), N);
    case C.Kind of
      2, 3: begin  // bus / truck: box body
              DPoly(Dest, [Q(0, 4), Q(L, 4), Q(L, H), Q(2, H)], Body);
              if C.Kind = 2 then
              begin
                for K := 0 to Trunc(L / 14) - 2 do
                  DPoly(Dest, [Q(6 + K * 14, H * 0.45), Q(16 + K * 14, H * 0.45), Q(16 + K * 14, H * 0.85),
                    Q(6 + K * 14, H * 0.85)], Mix(Glass, Hex('#FFE7A8'), N * 0.95));
                DPoly(Dest, [Q(0, H * 0.25), Q(L, H * 0.25), Q(L, H * 0.33), Q(0, H * 0.33)], Dark);
              end
              else
              begin
                DPoly(Dest, [Q(L - 24, 4), Q(L, 4), Q(L, H * 0.75), Q(L - 6, H * 0.8), Q(L - 24, H * 0.8)], Dark);
                DPoly(Dest, [Q(L - 18, H * 0.45), Q(L - 4, H * 0.45), Q(L - 6, H * 0.72), Q(L - 18, H * 0.72)], Glass);
              end;
            end;
    else
      begin  // sedan, taxi, van
        DPoly(Dest, [Q(0, 4), Q(L, 4), Q(L, H * 0.5), Q(L * 0.82, H * 0.56), Q(L * 0.7, H),
          Q(L * 0.28, H), Q(L * 0.14, H * 0.58), Q(0, H * 0.52)], Body);
        DPoly(Dest, [Q(L * 0.31, H * 0.6), Q(L * 0.48, H * 0.6), Q(L * 0.48, H * 0.92), Q(L * 0.3, H * 0.92)], Glass);
        DPoly(Dest, [Q(L * 0.51, H * 0.6), Q(L * 0.74, H * 0.6), Q(L * 0.67, H * 0.92), Q(L * 0.51, H * 0.92)], Glass);
        if C.Kind = 1 then  // taxi roof sign and checker stripe
        begin
          DPoly(Dest, [Q(L * 0.42, H), Q(L * 0.58, H), Q(L * 0.58, H + 4), Q(L * 0.42, H + 4)],
            Mix(Darken(Hex('#F2F2E8'), Sh), Hex('#FFF6C0'), N));
          DPoly(Dest, [Q(L * 0.05, H * 0.3), Q(L * 0.95, H * 0.3), Q(L * 0.95, H * 0.36), Q(L * 0.05, H * 0.36)],
            Darken(Hex('#1A1A1A'), Sh));
        end;
      end;
    end;
    for K := 0 to 1 do
    begin
      if K = 0 then R0 := L * 0.2 else R0 := L * 0.8;
      I := 6 + Ord(C.Kind in [2, 3]) * 2;
      DEllipse(Dest, Q(R0, I).X, Q(R0, I).Y, S(I), S(I), Hex('#151515'));
      DEllipse(Dest, Q(R0, I).X, Q(R0, I).Y, S(I * 0.45), S(I * 0.45), Darken(Hex('#9A9A9A'), Sh));
    end;
    DPoly(Dest, [Q(L - 2, H * 0.38), Q(L, H * 0.38), Q(L, H * 0.48), Q(L - 2, H * 0.48)],
      Mix(Hex('#F2F0E0'), Hex('#FFFFFF'), N));
    DPoly(Dest, [Q(0, H * 0.38), Q(2, H * 0.38), Q(2, H * 0.48), Q(0, H * 0.48)], Hex('#B02A20'));
    Exit;
  end;

  // ---- lights
  if not RowsHit(Y - H - 12, Y + 40) then Exit;
  if N > 0.05 then
  begin
    F := X + Dir * L / 2;
    // beam: a cone of light along the road and a bright pool where it lands
    DPolyG(Dest, [P(F, Y - H * 0.42), P(F + Dir * 170, Y - 3), P(F + Dir * 170, Y + 7), P(F, Y)],
      MakeGrad(WithAlpha(Hex('#FFF6DA'), Round(110 * N)), WithAlpha(Hex('#FFF6DA'), 0), False,
      P(F, 0), P(F + Dir * 170, 0)));
    Glow(Dest, F + Dir * 55, Y + 2, 44, WithAlpha(Hex('#FFF0C8'), Round(50 * N)));
    Glow(Dest, F - Dir * 1, Y - H * 0.43, 11, WithAlpha(Hex('#FFF8E6'), Round(255 * N)));
    Glow(Dest, F - Dir * 1, Y - H * 0.43, 4, WithAlpha(Hex('#FFFFFF'), Round(255 * N)));
  end;
  // tail / brake lights
  if C.Brake then TailK := 1 else TailK := N * 0.75;
  if FScene.FSeason = 1 then  // wet road: the lamps are mirrored as shimmering streaks
  begin
    if N > 0.05 then
      Streak(X + Dir * (L / 2 - 1), Hex('#FFF3D0'), N);
    if TailK > 0.03 then
      Streak(X - Dir * (L / 2 - 1), Hex('#FF3A2A'), TailK * 0.9);
  end;
  if TailK > 0.03 then
  begin
    F := X - Dir * (L / 2 - 1);
    Glow(Dest, F, Y - H * 0.43, 5 + 5 * TailK, WithAlpha(Hex('#FF2A1A'), Round(255 * TailK)));
    if N > 0.05 then  // red glow on the asphalt behind
      Glow(Dest, F - Dir * 14, Y + 3, 18 + 8 * Ord(C.Brake), WithAlpha(Hex('#FF2A1A'),
        Round((60 + 60 * Ord(C.Brake)) * N)));
  end;
  if N > 0.05 then
  begin
    if C.Kind = 1 then
      Glow(Dest, X, Y - H - 2, 12, WithAlpha(Hex('#FFF0A0'), Round(170 * N)));
    if C.Kind = 2 then
      for K := 0 to Trunc(L / 14) - 2 do
        Glow(Dest, X + Dir * (11 + K * 14 - L / 2), Y - H * 0.65, 11, WithAlpha(Hex('#FFE7A8'), Round(70 * N)));
  end;
end;

procedure TPainter.DrawTraffic(Dest: TBGRABitmap);
var
  I: Integer;
begin
  if not RowsHit(RoadTopY - 60, RoadBotY + 12) then Exit;
  // far lane first (behind), then the near lane
  for I := 0 to High(FScene.FCars) do
    with FScene.FCars[I] do
      if (Lane = 0) and (X > FScene.FVisL - 200) and (X < FScene.FVisR + 200) then
        DrawCar(Dest, FScene.FCars[I]);
  for I := 0 to High(FScene.FCars) do
    with FScene.FCars[I] do
      if (Lane = 1) and (X > FScene.FVisL - 200) and (X < FScene.FVisR + 200) then
        DrawCar(Dest, FScene.FCars[I]);
end;

{ An airliner: silhouette with a contrail by day, blinking lights at night. }
procedure TPainter.DrawPlane(Dest: TBGRABitmap);
var
  X, Y, N, Sh: Single;
  Body: TBGRAPixel;
begin
  X := FScene.FPlaneX;
  Y := FScene.FPlaneY;
  if (X < FScene.FVisL - 80) or (X > FScene.FVisR + 600) then Exit;
  if not RowsHit(Y - 20, Y + 20) then Exit;
  N := FScene.Night;
  Sh := FScene.Shade;
  if FPart = 0 then
  begin
    if N < 0.6 then  // contrail: a long paper strip
      DPolyG(Dest, [P(X + 22, Y - 1.5), P(X + 520, Y - 4), P(X + 520, Y + 4), P(X + 22, Y + 1.5)],
        MakeGrad(WithAlpha(BGRA(255, 255, 255), Round(220 * (1 - N))), BGRA(255, 255, 255, 0), False,
        P(X + 22, 0), P(X + 520, 0)));
    Body := Darken(Hex('#DADDE2'), Sh);
    DPoly(Dest, [P(X - 24, Y), P(X - 18, Y - 3), P(X + 20, Y - 3), P(X + 26, Y - 11), P(X + 30, Y - 11),
      P(X + 28, Y - 2), P(X + 26, Y + 2), P(X - 18, Y + 3)], Body);
    DPoly(Dest, [P(X - 2, Y), P(X + 10, Y), P(X + 18, Y + 10), P(X + 12, Y + 10)], Darken(Body, 0.82));
  end
  else if N > 0.05 then
  begin
    Glow(Dest, X + 14, Y + 9, 6, WithAlpha(Hex('#FF2A1A'), Round(255 * N)));
    Glow(Dest, X + 4, Y - 4, 5, WithAlpha(Hex('#2AFF6A'), Round(255 * N)));
    Glow(Dest, X - 23, Y, 6, WithAlpha(Hex('#FFF6DA'), Round(220 * N)));  // landing light
    if Frac(FScene.FTime / 1.1) < 0.12 then
      Glow(Dest, X + 28, Y - 11, 14, WithAlpha(Hex('#FFFFFF'), Round(255 * N)));
    if Frac(FScene.FTime / 1.1 + 0.5) < 0.1 then
      Glow(Dest, X + 2, Y + 3, 9, WithAlpha(Hex('#FF3020'), Round(200 * N)));  // belly beacon
  end;
end;

procedure TPainter.DrawBirds(Dest: TBGRABitmap);
var
  I, A: Integer;
  Tip, Sz: Single;
  C: TBGRAPixel;
begin
  if (FPart <> 0) or (FScene.FSeason = 1) then Exit;
  A := Round(255 * (1 - FScene.Night));
  if A < 10 then Exit;
  C := WithAlpha(Hex('#2A2A30'), A);
  for I := 0 to High(FScene.FBirds) do
    with FScene.FBirds[I] do
    begin
      if not RowsHit(Y - 10, Y + 10) then Continue;
      Sz := Size;
      Tip := -Sz * 0.7 * Sin(Phase);
      // two paper wings
      DPoly(Dest, [P(X - Sz, Y + Tip), P(X - Sz * 0.45, Y - Sz * 0.25 + Tip * 0.3), P(X, Y),
        P(X - Sz * 0.45, Y + Sz * 0.12 + Tip * 0.3)], C);
      DPoly(Dest, [P(X + Sz, Y + Tip), P(X + Sz * 0.45, Y - Sz * 0.25 + Tip * 0.3), P(X, Y),
        P(X + Sz * 0.45, Y + Sz * 0.12 + Tip * 0.3)], C);
    end;
end;

{ Weather of the season. Every drop / flake / spark is a pure function of its
  index and the scene time (hash based), so the layer has no state to keep,
  costs nothing to copy and replays exactly in an export.
    rainy:  450 slanted streaks, ripples on the river, splashes on the road,
            lightning: a jagged bolt and a flash over the whole picture
    winter: 420 flakes in three sizes, swaying as they fall
    summer: fireworks over the river at night (rockets, bursts with gravity,
            a flash and its glow on the water) }
procedure TPainter.DrawWeather(Dest: TBGRABitmap);
const
  Sparks: array[0..4] of string = ('#FF5A4A', '#FFD24A', '#6AE0FF', '#C67AFF', '#7AFF8A');
var
  Sc: TCityScene;
  I, K, A: Integer;
  T, N, X, Y, Span, H1, H2, H3, Spd, Len, VX, P0, R, Sw, Ph, Cycle, Life, Ang, PX, PY: Single;
  C: TBGRAPixel;
  Pts: array of TPointF;
begin
  Sc := FScene;
  T := Sc.FTime;
  N := Sc.Night;
  Span := Sc.FVisR - Sc.FVisL + 160;
  case Sc.FSeason of
    1: begin
         VX := -110;
         C := Mix(BGRA(214, 224, 238), BGRA(170, 186, 214), N);
         for I := 0 to 449 do
         begin
           H1 := Hash01(I * 3 + 11);
           H2 := Hash01(I * 3 + 12);
           H3 := Hash01(I * 3 + 13);
           Spd := 560 + 300 * H3;
           Len := 12 + 16 * H3;
           P0 := PFrac(H2 + T * Spd / (DesignH + 80));
           Y := -40 + P0 * (DesignH + 80);
           if not RowsHit(Y, Y + Len) then Continue;
           X := Sc.FVisL - 80 + PFrac(H1 + VX * P0 * (DesignH + 80) / Spd / Span) * Span;
           RainStreak(Dest, X, Y, VX * Len / Spd, Len, 0.9 + 0.6 * H3, WithAlpha(C, Round(70 + 90 * H3)));
         end;
         // ripples on the river, splashes on the road: a new place every cycle
         C := Mix(BGRA(230, 238, 248), BGRA(160, 175, 205), N);
         for I := 0 to 69 do
         begin
           H2 := Hash01(I * 5 + 102);
           Cycle := T / 0.9 + Hash01(I * 5 + 103);
           Ph := PFrac(Cycle);
           X := Sc.FVisL + Hash01(I * 7 + Floor(Cycle) * 131) * (Sc.FVisR - Sc.FVisL);
           if I < 45 then Y := CityBaseY + 8 + H2 * (RiverBotY - CityBaseY - 14)
           else Y := RoadTopY + 6 + H2 * (RoadBotY - RoadTopY - 10);
           R := 1.5 + 7 * Ph;
           A := Round(150 * (1 - Ph));
           HDash(Dest, X - R, Y - R * 0.3, 2 * R, 0.9, WithAlpha(C, A));
           HDash(Dest, X - R * 0.8, Y + R * 0.3, 1.6 * R, 0.9, WithAlpha(C, A div 2));
         end;
         // lightning
         if Sc.FFlash > 0.01 then
         begin
           if Sc.FBoltOn and (Length(Sc.FBolt) > 1) and RowsHit(0, CityBaseY) then
           begin
             SetLength(Pts, Length(Sc.FBolt));
             for I := 0 to High(Pts) do Pts[I] := P(Sc.FBolt[I].X, Sc.FBolt[I].Y);
             DPolyLine(Dest, Pts, BGRA(190, 200, 255, 90), Max(2, S(8)));
             DPolyLine(Dest, Pts, BGRA(255, 255, 255, 245), Max(1, S(2.4)));
           end;
           if FRaster then
             Dest.FillRect(0, 0, Dest.Width, Dest.Height, BGRA(225, 230, 255, Round(85 * Sc.FFlash)),
               dmDrawWithTransparency);
         end;
       end;
    2: begin
         C := Mix(BGRA(255, 255, 255), BGRA(214, 224, 245), N);
         for I := 0 to 419 do
         begin
           H1 := Hash01(I * 3 + 41);
           H2 := Hash01(I * 3 + 42);
           H3 := Hash01(I * 3 + 43);
           Spd := 22 + 60 * H3;
           R := 1 + 2.6 * H3;
           P0 := PFrac(H2 + T * Spd / (DesignH + 40));
           Y := -20 + P0 * (DesignH + 40);
           if not RowsHit(Y - R, Y + R) then Continue;
           Sw := Sin(T * (0.8 + H1) + I) * (6 + 14 * H3);
           X := Sc.FVisL - 80 + PFrac(H1 + T * (8 + 10 * H3) / Span) * Span + Sw;
           DEllipse(Dest, P(X, Y).X, P(X, Y).Y, S(R), S(R), WithAlpha(C, Round(150 + 100 * H3)));
         end;
       end;
  else
    if N > 0.35 then
      for K := 0 to 2 do
      begin
        Cycle := T / 4.6 + K * 0.37;
        Life := Floor(Cycle);
        Ph := (Cycle - Life) * 4.6;  // seconds into this firework
        X := 250 + Hash01(K * 97 + Round(Life) * 13) * 1100;
        Y := 110 + Hash01(K * 31 + Round(Life) * 7) * 170;
        C := Hex(Sparks[(K + Round(Life)) mod 5]);
        if Ph < 0.9 then
        begin  // the rocket rises from the river
          PY := CityBaseY + 10 - (CityBaseY + 10 - Y) * (1 - Sqr(1 - Ph / 0.9));
          if RowsHit(PY - 6, PY + 34) then
          begin
            DLine(Dest, P(X, PY).X, P(X, PY).Y, P(X, 0).X, P(0, PY + 30).Y, WithAlpha(Hex('#FFD9A0'), Round(110 * N)),
              Max(0.6, S(1.2)));
            Glow(Dest, X, PY, 5, WithAlpha(Hex('#FFF0C8'), Round(255 * N)));
          end;
        end
        else
        begin
          Life := (Ph - 0.9) / 2.6;  // 0..1 over the burst
          if Life > 1 then Continue;
          R := 100 * (1 - Sqr(1 - Min(1, Life * 1.6)));
          if Life < 0.15 then
            Glow(Dest, X, Y, 70, WithAlpha(C, Round(140 * N * (1 - Life / 0.15))));
          Glow(Dest, X, CityBaseY + 50, 80, WithAlpha(C, Round(45 * N * (1 - Life))));  // on the water
          for I := 0 to 29 do
          begin
            Ang := I * 2 * Pi / 30 + K;
            PX := X + Cos(Ang) * R;
            PY := Y + Sin(Ang) * R * 0.9 + 45 * Sqr(Life);
            A := Round(255 * N * (1 - Life));
            Glow(Dest, PX, PY, 5 - 2 * Life, WithAlpha(C, A));
            if not Odd(I) then
              Glow(Dest, X + Cos(Ang) * R * 0.6, Y + Sin(Ang) * R * 0.55 + 45 * Sqr(Life), 3,
                WithAlpha(Mix(C, Hex('#FFFFFF'), 0.5), A));
          end;
        end;
      end;
  end;
end;

procedure TPainter.RenderBand(Dest: TBGRABitmap; ATop: Integer);
var
  Sc: TCityScene;
  Y, W, H, A, M, R, MT, MB, LTop, LH: Integer;
  T0: Double;
  Q: TPointF;

  procedure Mark(Id: TLayerId);
  var
    T: Double;
  begin
    T := HiResMs;
    LayerMs[Id] := LayerMs[Id] + (T - T0);
    T0 := T;
  end;

  { a static part cut for each palette: the "from" set, then the "to" set faded in }
  procedure Pair(const Arr: array of TBGRABitmap; const Pos: TPoint; const Svg: array of string);
  begin
    if FSvg <> nil then FSvg.Raw(Svg[M]);
    if not FRaster then Exit;
    BlendBitmap(Dest, Pos.X, Pos.Y - ATop, Arr[Sc.FFrom]);
    if (Sc.FFrom <> Sc.FTo) and (A > 0) then
      BlendBitmap(Dest, Pos.X, Pos.Y - ATop, Arr[Sc.FTo], A);
  end;

  { a light sprite faded in by the night amount }
  procedure Lights(Spr: TBGRABitmap; const Pos: TPoint; const Svg: string);
  var
    L: Integer;
  begin
    L := Round(255 * Sc.Night);
    if L < 3 then Exit;
    if FSvg <> nil then
      FSvg.Raw('<g opacity="' + FSvg.N(L / 255) + '">' + LineEnding + Svg + '</g>');
    if FRaster then BlendBitmap(Dest, Pos.X, Pos.Y - ATop, Spr, L);
  end;

  { a live paper layer: the paper parts on the band's work layer, composited
    with a soft shadow, then the lights of the same objects on top }
  procedure Shadowed(Id: TLayerId; Y0, Y1: Single; Proc: TDrawProc);
  begin
    TargetBand(ATop, H);
    if RowsHit(Y0, Y1 + 30) then
    begin
      if FRaster then
      begin
        if (FLayer.Width <> W) or (FLayer.Height <> LH) then FLayer.SetSize(W, LH);
        FLayerTop := LTop;
        // only the rows this layer can draw on (with a little slack)
        FRowA := Floor(Sc.FOffY + (Y0 - 12) * Sc.FScale) - LTop;
        FRowB := Ceil(Sc.FOffY + (Y1 + 12) * Sc.FScale) - LTop;
      end
      else
        FLayerTop := 0;
      FPart := 0;
      BeginLayer;
      Proc(FLayer);
      CompositeLayer(Dest, ATop, LayerDepth[Id]);
      TargetBand(ATop, H);
    end;
    FPart := 1;
    Proc(Dest);
    FPart := 0;
  end;

begin
  Sc := FScene;
  W := Sc.FWidth;
  if Dest <> nil then H := Dest.Height else H := Sc.FHeight;
  T0 := HiResMs;
  A := Round(255 * Sc.FBlend);
  M := Sc.CurrentMode;
  // the work layer covers the band plus the rows whose shadows reach into it;
  // its top is a multiple of 4 so every band samples the same shadow grid
  R := Max(1, Round(S(7) * MaxDepth / 4));
  MB := (2 * R + 3) * 4;
  MT := Round(S(6) * MaxDepth) + MB;
  LTop := Floor((ATop - MT) / 4) * 4;
  LH := ATop + H + MB - LTop;
  TargetBand(ATop, H);

  if Sc.LayerOn[lySky] then
  begin
    if FSvg <> nil then FSvg.Raw(Sc.FSvgSky[M]);
    if FRaster then
    begin
      for Y := 0 to H - 1 do
        if ATop + Y < Sc.FHeight then
          Move(RowPtr(Sc.FSky[Sc.FFrom], ATop + Y)^, RowPtr(Dest, Y)^, W * SizeOf(TBGRAPixel));
      if (Sc.FFrom <> Sc.FTo) and (A > 0) then
        BlendBitmap(Dest, 0, -ATop, Sc.FSky[Sc.FTo], A);
    end;
  end
  else if FRaster then
    if Sc.TransparentBack then Dest.FillTransparent else Dest.Fill(BGRA(120, 140, 170));
  Mark(lySky);

  if Sc.LayerOn[lyStars] then DrawStars(Dest);
  Mark(lyStars);
  if Sc.LayerOn[lyClouds] then DrawClouds(Dest);
  Mark(lyClouds);
  if Sc.LayerOn[lyFarCity] then Pair(Sc.FFar, Sc.FFarPos, Sc.FSvgFar);
  Mark(lyFarCity);
  if Sc.LayerOn[lyCity] then
  begin
    Pair(Sc.FCity, Sc.FCityPos, Sc.FSvgCity);
    Shadowed(lyCity, CityBaseY - 320, CityBaseY - 90, @DrawCraneLoad);
  end;
  Mark(lyCity);
  if Sc.LayerOn[lyWindowLights] then
  begin
    Lights(Sc.FWinLights, Sc.FWinPos, Sc.FSvgWinLights);
    DrawFlicker(Dest);
  end;
  Mark(lyWindowLights);
  if Sc.LayerOn[lyLandmarkLights] then DrawLandmarkLights(Dest);
  Mark(lyLandmarkLights);
  if Sc.LayerOn[lyRiver] then
  begin
    Pair(Sc.FRiver, Sc.FRiverPos, Sc.FSvgRiver);
    DrawWaves(Dest);
    Pair(Sc.FLib, Sc.FLibPos, Sc.FSvgLib);
  end;
  Mark(lyRiver);
  if Sc.LayerOn[lyReflections] then DrawReflections(Dest);
  Mark(lyReflections);
  if Sc.LayerOn[lyBridge] then Pair(Sc.FBridge, Sc.FBridgePos, Sc.FSvgBridge);
  Mark(lyBridge);
  if Sc.LayerOn[lyBridgeLights] then Lights(Sc.FBridgeLights, Sc.FBridgeLPos, Sc.FSvgBridgeLights);
  Mark(lyBridgeLights);
  if Sc.LayerOn[lyBridgeTraffic] then Shadowed(lyBridgeTraffic, DeckY - 20, DeckY + 10, @DrawBridgeTraffic);
  Mark(lyBridgeTraffic);
  if Sc.LayerOn[lyBoats] then Shadowed(lyBoats, DeckY, RiverBotY, @DrawBoats);
  Mark(lyBoats);
  if Sc.LayerOn[lyStreet] then
  begin
    Pair(Sc.FStreet, Sc.FStreetPos, Sc.FSvgStreet);
    DrawSignal(Dest);
  end;
  Mark(lyStreet);
  if Sc.LayerOn[lyStreetLights] then Lights(Sc.FStreetGlow, Sc.FGlowPos, Sc.FSvgStreetGlow);
  Mark(lyStreetLights);
  if Sc.LayerOn[lyTraffic] then Shadowed(lyTraffic, RoadTopY - 60, RoadBotY + 10, @DrawTraffic);
  Mark(lyTraffic);
  if Sc.LayerOn[lyPlane] then Shadowed(lyPlane, Sc.FPlaneY - 20, Sc.FPlaneY + 20, @DrawPlane);
  Mark(lyPlane);
  if Sc.LayerOn[lyBirds] then Shadowed(lyBirds, 150, 420, @DrawBirds);
  Mark(lyBirds);
  TargetBand(ATop, H);
  if Sc.LayerOn[lyWeather] then DrawWeather(Dest);
  // a season change: the picture from before fades out on top
  if FRaster and (Sc.FSnap <> nil) and (Sc.FSnapFade > 0) then
    BlendBitmap(Dest, 0, -ATop, Sc.FSnap, Round(255 * Sc.FSnapFade));
  Mark(lyWeather);
  if Sc.FShowCaption and Sc.LayerOn[lyCaption] and (Sc.FCaption <> nil) then
  begin
    Q := P(20, 18);
    if FSvg <> nil then
      FSvg.Raw(Format('<g transform="translate(%s,%s)">', [FSvg.N(Round(Q.X)), FSvg.N(Round(Q.Y))]) +
        LineEnding + Sc.FSvgCaption + '</g>');
    if FRaster then BlendBitmap(Dest, Round(Q.X), Round(Q.Y), Sc.FCaption);
  end;
  Mark(lyCaption);
  if Dest <> nil then Dest.InvalidateBitmap;
end;

{ ====================================================================== }
{ TCityScene                                                             }
{ ====================================================================== }

constructor TCityScene.Create;
begin
  inherited Create;
  FShowCaption := True;
  FillChar(LayerOn, SizeOf(LayerOn), 1);
  FVisL := 0;
  FVisR := DesignW;
  FScale := 1;
  AutoSeconds := 14;
  FadeSeconds := 2.2;
  FFrom := 2;
  FTo := 2;
  FSeason := 0;
  FPendingSeason := -1;
  FFlashT := 10;
  FFlashNext := 3;
  FBlend := 0;
  FCutter := TPainter.Create(Self);
  FAcc := TBGRABitmap.Create(1, 1);
  MakePalettes;
  Generate;
end;

destructor TCityScene.Destroy;
begin
  FreeResources;
  FCutter.Free;
  FAcc.Free;
  FSnap.Free;
  FStaticSvg.Free;
  inherited Destroy;
end;

function TCityScene.P(X, Y: Single): TPointF;
begin
  Result := FCutter.P(X, Y);
end;

function TCityScene.S(V: Single): Single;
begin
  Result := V * FScale;
end;

procedure TCityScene.MakePalettes;
var
  I: Integer;

  procedure Fac(var Pl: TPal; const A, B, C, D: string);
  begin
    Pl.Facade[0] := Hex(A); Pl.Facade[1] := Hex(B); Pl.Facade[2] := Hex(C); Pl.Facade[3] := Hex(D);
  end;

begin
  with FPal[0] do  // morning
  begin
    SkyTop := Hex('#5F86C2'); SkyBot := Hex('#F7B98B'); Glow := Hex('#FFD3A0'); SunC := Hex('#FFE2A8');
    Far := Hex('#9C8FA6'); Haze := Hex('#D9B6A8'); Glass := Hex('#A8B5D2'); Win := Hex('#717892');
    Water1 := Hex('#7C93BE'); Water2 := Hex('#3C5A86'); Road := Hex('#4C4C54'); Walk := Hex('#948E8A');
    Stone := Hex('#A08A74'); Cable := Hex('#5C5048'); Tree := Hex('#4E6E3E'); Liberty := Hex('#7FB0A0');
    CloudLit := Hex('#FFD9C6'); CloudShade := Hex('#B48EA6');
    SunX := 175; SunY := 300; SunR := 34; Moon := False;
  end;
  Fac(FPal[0], '#C2A58E', '#A3938C', '#CDB79E', '#9796AC');
  with FPal[1] do  // day
  begin
    SkyTop := Hex('#2F74CC'); SkyBot := Hex('#BEE3F7'); Glow := Hex('#FFFFFF'); SunC := Hex('#FFF4C8');
    Far := Hex('#AFC0D2'); Haze := Hex('#C9DCEC'); Glass := Hex('#9FC3E6'); Win := Hex('#7F95AE');
    Water1 := Hex('#3F86BA'); Water2 := Hex('#1F4F7E'); Road := Hex('#57585E'); Walk := Hex('#ABA8A4');
    Stone := Hex('#B49E84'); Cable := Hex('#6A5E54'); Tree := Hex('#4F8A3A'); Liberty := Hex('#6FAE98');
    CloudLit := Hex('#FFFFFF'); CloudShade := Hex('#B5C3D3');
    SunX := 1290; SunY := 115; SunR := 28; Moon := False;
  end;
  Fac(FPal[1], '#CBC7BF', '#A6A9AF', '#DAD0C2', '#8FA0B4');
  with FPal[2] do  // night
  begin
    SkyTop := Hex('#050918'); SkyBot := Hex('#1C2452'); Glow := Hex('#4A3A62'); SunC := Hex('#F2EED8');
    Far := Hex('#141936'); Haze := Hex('#1E2448'); Glass := Hex('#1E2540'); Win := Hex('#10131F');
    Water1 := Hex('#141C40'); Water2 := Hex('#050818'); Road := Hex('#17181E'); Walk := Hex('#26262E');
    Stone := Hex('#2E2A34'); Cable := Hex('#22202A'); Tree := Hex('#141E16'); Liberty := Hex('#2A4A44');
    CloudLit := Hex('#3A4070'); CloudShade := Hex('#1A1F3E');
    SunX := 1330; SunY := 110; SunR := 22; Moon := True;
  end;
  Fac(FPal[2], '#1C2034', '#20243A', '#191C2E', '#232842');
  for I := 0 to 2 do
    SeasonTint(FPal[I], I);
end;

{ The base palettes are summer-ish; each season shifts them. }
procedure TCityScene.SeasonTint(var Pl: TPal; M: Integer);
var
  I: Integer;
  K: Single;
begin
  K := ModeShade[M];
  Pl.Snow := Pl.Walk;
  Pl.SunHidden := False;
  case FSeason of
    0: begin  // summer: deeper blue, lush green, bright water
         if M <> 2 then Pl.SkyTop := Mix(Pl.SkyTop, Hex('#1C64D8'), 0.25);
         Pl.Tree := Mix(Pl.Tree, Darken(Hex('#3FA83A'), K), 0.45);
         Pl.Water1 := Mix(Pl.Water1, Darken(Hex('#2E9AC8'), K), 0.25);
       end;
    1: begin  // rainy: grey overcast, wet dark street, the sun hidden
         if M = 2 then
         begin
           Pl.SkyTop := Hex('#0A0D15');
           Pl.SkyBot := Hex('#2C2930');
           Pl.Glow := Hex('#8A6248');  // city light reflected by the low clouds
         end
         else
         begin
           Pl.SkyTop := Darken(GreyMix(Pl.SkyTop, 0.75), 0.68);
           Pl.SkyBot := Darken(GreyMix(Pl.SkyBot, 0.7), 0.76);
           Pl.Glow := GreyMix(Pl.Glow, 0.6);
         end;
         Pl.SunHidden := True;
         Pl.Far := GreyMix(Pl.Far, 0.5);
         Pl.Haze := GreyMix(Pl.Haze, 0.6);
         for I := 0 to 3 do Pl.Facade[I] := Darken(GreyMix(Pl.Facade[I], 0.35), 0.8);
         Pl.Glass := Darken(GreyMix(Pl.Glass, 0.4), 0.85);
         Pl.Water1 := Darken(GreyMix(Pl.Water1, 0.5), 0.82);
         Pl.Water2 := Darken(GreyMix(Pl.Water2, 0.5), 0.8);
         Pl.Road := Darken(Pl.Road, 0.72);
         Pl.Walk := Darken(Pl.Walk, 0.78);
         Pl.Stone := Darken(Pl.Stone, 0.85);
         Pl.Tree := Darken(Pl.Tree, 0.78);
         Pl.CloudLit := Darken(Hex('#AEB4BD'), K);
         Pl.CloudShade := Darken(Hex('#7A818C'), K);
       end;
    2: begin  // winter: cold pale sky, snow everywhere, icy river, bare trees
         if M = 2 then
         begin
           Pl.SkyTop := Hex('#070C1C');
           Pl.SkyBot := Hex('#26324F');
           Pl.Snow := Hex('#56628A');
         end
         else
         begin
           Pl.SkyTop := Mix(Pl.SkyTop, Hex('#93AACB'), 0.45);
           Pl.SkyBot := Mix(Pl.SkyBot, Hex('#E4ECF3'), 0.5);
           if M = 0 then Pl.Snow := Hex('#EFE2DC') else Pl.Snow := Hex('#F1F5F9');
           Pl.CloudLit := Hex('#FFFFFF');
         end;
         Pl.Walk := Pl.Snow;
         for I := 0 to 3 do Pl.Facade[I] := Mix(Pl.Facade[I], Darken(Hex('#B8C2CC'), K), 0.2);
         Pl.Water1 := Mix(Pl.Water1, Darken(Hex('#9DB8C8'), K), 0.45);
         Pl.Water2 := Mix(Pl.Water2, Darken(Hex('#5C7C93'), K), 0.45);
         Pl.Road := Mix(Pl.Road, Darken(Hex('#7E858E'), K), 0.3);
         Pl.Tree := Darken(Hex('#4A3A30'), Max(0.5, K));  // bare branches
         Pl.CloudShade := Mix(Pl.CloudShade, Darken(Hex('#B4C2D0'), K), 0.5);
       end;
  end;
end;

{ The city is generated once (fixed seed): two rows of towers, distant
  silhouettes, roof beacons, stars, clouds, lamps, traffic, boats, birds. }
procedure TCityScene.Generate;
var
  X, W, H: Single;
  I, N: Integer;

  procedure AddB(AX, AW, AH, ABase: Single; Back: Boolean);
  var
    B: TBuilding;
    K: Integer;
  begin
    B.X := AX; B.W := AW; B.H := AH; B.BaseY := ABase; B.Back := Back;
    B.Tone := Random(4);
    B.Var_ := RandRange(-0.08, 0.08);
    B.Tiers := 0;
    if AH > 200 then B.Tiers := Random(3);
    for K := 0 to 1 do
    begin
      B.TierInset[K] := RandRange(0.1, 0.18) * (K + 1);
      B.TierH[K] := RandRange(18, 55);
    end;
    if (AH < 240) and (Random < 0.35) then B.Roof := 2
    else if Random < 0.3 then B.Roof := 1
    else if Random < 0.2 then B.Roof := 3
    else B.Roof := 0;
    B.LitProb := RandRange(0.22, 0.62);
    SetLength(FBuildings, Length(FBuildings) + 1);
    FBuildings[High(FBuildings)] := B;
    if AH > 300 then
    begin
      SetLength(FBeacons, Length(FBeacons) + 1);
      FBeacons[High(FBeacons)] := PointF(AX + AW / 2, ABase - AH - 3);
    end;
  end;

begin
  RandSeed := 1977;
  // back row: taller, hazier
  X := -1200;
  while X < 2800 do
  begin
    W := RandRange(40, 96);
    H := Env(X + W / 2) * RandRange(0.8, 1.15) + RandRange(-30, 30);
    AddB(X, W, Max(60, H), CityBaseY - 4, True);
    X := X + W + RandRange(-8, 4);
  end;
  // front row: lower, closer
  X := -1200;
  while X < 2800 do
  begin
    W := RandRange(34, 80);
    H := Env(X + W / 2) * RandRange(0.35, 0.6) + RandRange(-20, 20);
    if (X + W > 545) and (X < 690) then H := Min(H, 120);   // keep the Empire State visible
    if (X + W > 745) and (X < 855) then H := Min(H, 140);   // Chrysler
    if (X + W > 1135) and (X < 1285) then H := Min(H, 60);  // One WTC
    if (X + W > 950) and (X < 1035) then H := Min(H, 60);   // crane site
    AddB(X, W, Max(40, H), CityBaseY, False);
    X := X + W + RandRange(-4, 6);
  end;
  FBeacons := Concat(FBeacons, [PointF(615, CityBaseY - 522), PointF(800, CityBaseY - 412),
    PointF(1210, CityBaseY - 497)]);
  // distant skyline
  X := -1200;
  SetLength(FFarRects, 0);
  while X < 2800 do
  begin
    W := RandRange(14, 46);
    H := RandRange(14, 70) + 30 * Exp(-Sqr((X - 1500) / 300));
    SetLength(FFarRects, Length(FFarRects) + 1);
    FFarRects[High(FFarRects)] := RectF(X, FarBaseY - H, X + W, FarBaseY + 20);
    X := X + W + RandRange(-4, 10);
  end;
  // stars
  SetLength(FStars, 260);
  for I := 0 to High(FStars) do
    with FStars[I] do
    begin
      X := RandRange(-800, 2400);
      Y := RandRange(8, 470) * Power(Random, 0.3);
      R := RandRange(0.6, 1.7);
      Phase := RandRange(0, 6);
    end;
  // clouds
  SetLength(FClouds, 7);
  for I := 0 to High(FClouds) do
    AddCloud(I, RandRange(-200, 1800), RandRange(60, 330), RandRange(180, 320), RandRange(40, 70),
      IfThen(Odd(I), -1, 1) * RandRange(6, 14));
  // lamps every 210 design px
  SetLength(FLamps, 0);
  X := -1260;
  while X < 2860 do
  begin
    SetLength(FLamps, Length(FLamps) + 1);
    FLamps[High(FLamps)] := X;
    X := X + 210;
  end;
  // road traffic
  N := 18;
  SetLength(FCars, N);
  for I := 0 to N - 1 do
    SpawnCar(FCars[I], I mod 2, -900 + (I div 2) * 300 + RandRange(0, 120));
  // bridge traffic
  SetLength(FBridgeCars, 22);
  for I := 0 to High(FBridgeCars) do
    with FBridgeCars[I] do
    begin
      X := RandRange(-800, 2400);
      Dir := IfThen(Odd(I), -1, 1);
      Speed := RandRange(60, 95);
      case Random(5) of
        0: Color := Hex('#F7C21B');
        1: Color := Hex('#C83A2A');
        2: Color := Hex('#E8E8E8');
        3: Color := Hex('#2A4A8A');
      else
        Color := Hex('#404448');
      end;
    end;
  FTrainX := -400;
  FTrainWait := 3;
  // boats
  SetLength(FBoats, 3);
  FBoats[0].X := 300; FBoats[0].Y := 712; FBoats[0].Speed := 22; FBoats[0].Size := 1.1; FBoats[0].Kind := 0;
  FBoats[1].X := 1300; FBoats[1].Y := 700; FBoats[1].Speed := -15; FBoats[1].Size := 1; FBoats[1].Kind := 1;
  FBoats[2].X := 900; FBoats[2].Y := 730; FBoats[2].Speed := 12; FBoats[2].Size := 0.9; FBoats[2].Kind := 2;
  // plane
  FPlaneX := 1900;
  FPlaneY := 150;
  FPlaneWait := 0;
  // birds
  SetLength(FBirds, 9);
  for I := 0 to High(FBirds) do
    with FBirds[I] do
    begin
      X := RandRange(0, 1600);
      Y := RandRange(180, 380);
      VX := RandRange(30, 55);
      Size := RandRange(5, 9);
      Phase := RandRange(0, 6);
    end;
end;

procedure TCityScene.SpawnCar(var C: TCar; Lane: Integer; X: Single);
begin
  C.Lane := Lane;
  C.X := X;
  C.Kind := Random(10);
  case C.Kind of
    0..3: begin C.Kind := 0; C.Len := 52; C.H := 19; end;
    4..6: begin C.Kind := 1; C.Len := 52; C.H := 19; end;   // taxi
    7: begin C.Kind := 2; C.Len := 118; C.H := 36; end;      // bus
    8: begin C.Kind := 3; C.Len := 92; C.H := 34; end;       // truck
  else
    begin C.Kind := 4; C.Len := 60; C.H := 24; end;          // van
  end;
  C.Cruise := RandRange(70, 105) * IfThen(C.Kind in [2, 3], 0.8, 1);
  C.Speed := C.Cruise;
  case C.Kind of
    1: C.Color := Hex('#F7C21B');
    2: C.Color := Hex('#2F6FD0');
    3: C.Color := Hex('#E6E2D8');
  else
    case Random(6) of
      0: C.Color := Hex('#C83A2A');
      1: C.Color := Hex('#2A2E36');
      2: C.Color := Hex('#E8E8E8');
      3: C.Color := Hex('#2A4A8A');
      4: C.Color := Hex('#6A7A84');
    else
      C.Color := Hex('#3E6A4A');
    end;
  end;
end;

procedure TCityScene.AddCloud(Index: Integer; CX, CY, W, H, Speed: Single);
var
  C: TCloud;
  I, NB, K: Integer;
  U, X, Y, R: Single;
begin
  NB := 14 + Random(8);
  SetLength(C.Puffs, 3 * NB);
  K := 0;
  for I := 0 to NB - 1 do
  begin
    // domes are bigger in the middle; their bottoms sit near a flat base line
    if I < 3 then U := RandRange(-0.18, 0.18) else U := RandRange(-0.5, 0.5);
    R := H * RandRange(0.3, 0.55) * (1 - 1.1 * Abs(U)) + H * 0.08;
    C.Puffs[K] := CX + U * W;
    C.Puffs[K + 1] := CY + H * 0.25 - R * RandRange(0.35, 0.8);
    C.Puffs[K + 2] := R;
    Inc(K, 3);
  end;
  C.MinX := 1e9; C.MaxX := -1e9; C.MinY := 1e9; C.MaxY := -1e9;
  I := 0;
  while I + 2 <= High(C.Puffs) do
  begin
    X := C.Puffs[I]; Y := C.Puffs[I + 1]; R := C.Puffs[I + 2];
    C.MinX := Min(C.MinX, X - R); C.MaxX := Max(C.MaxX, X + R);
    C.MinY := Min(C.MinY, Y - R); C.MaxY := Max(C.MaxY, Y + R);
    Inc(I, 3);
  end;
  C.OX := 0;
  C.Speed := Speed;
  for I := 0 to 2 do
  begin
    C.Sprite[I] := nil;
    C.Svg[I] := '';
  end;
  FClouds[Index] := C;
end;

procedure TCityScene.FreeResources;
var
  M, I: Integer;
begin
  for M := 0 to 2 do
  begin
    FreeAndNil(FSky[M]);
    FreeAndNil(FFar[M]);
    FreeAndNil(FCity[M]);
    FreeAndNil(FRiver[M]);
    FreeAndNil(FBridge[M]);
    FreeAndNil(FStreet[M]);
    FreeAndNil(FLib[M]);
    for I := 0 to High(FClouds) do
      FreeAndNil(FClouds[I].Sprite[M]);
  end;
  FreeAndNil(FWinLights);
  FreeAndNil(FBridgeLights);
  FreeAndNil(FStreetGlow);
  FreeAndNil(FCaption);
end;

procedure TCityScene.Resize(AWidth, AHeight: Integer);
var
  T0: Double;
begin
  T0 := HiResMs;
  FreeAndNil(FSnap);  // a fade in progress belongs to the old size
  FWidth := Max(1, AWidth);
  FHeight := Max(1, AHeight);
  FScale := Min(FWidth / DesignW, FHeight / DesignH);
  FOffX := Round((FWidth - DesignW * FScale) / 2);
  FOffY := Round((FHeight - DesignH * FScale) / 2);
  FVisL := -FOffX / FScale;
  FVisR := (FWidth - FOffX) / FScale;
  FreeResources;
  FCutter.FLayer.SetSize(FWidth, FHeight);
  FCutter.FLayerTop := 0;
  FCutter.FRowA := 0;
  FCutter.FRowB := MaxInt;  // static cut: the whole layer
  FAcc.SetSize(FWidth, FHeight);
  FreeAndNil(FStaticSvg);
  if FRecordSvg then FStaticSvg := TSvgRecorder.Create('s');
  FCutter.FSvg := FStaticSvg;
  try
    RenderStatic;
  finally
    FCutter.FSvg := nil;
  end;
  StaticMs := HiResMs - T0;
  Inc(StaticCount);
end;

function TCityScene.SpriteJobCount: Integer;
begin
  Result := 0;
end;

procedure TCityScene.SpriteJob(AIndex, AWorker: Integer);
begin
end;

function TCityScene.Crop(Y0, Y1: Single; out Pos: TPoint): TBGRABitmap;
var
  A, B: Integer;
begin
  A := EnsureRange(Floor(P(0, Y0).Y), 0, FHeight - 1);
  B := EnsureRange(Ceil(P(0, Y1).Y), A + 1, FHeight);
  Pos := Point(0, A);
  Result := TBGRABitmap(FAcc.GetPart(Rect(0, A, FWidth, B)));
  Result.LoadFromBitmapIfNeeded;
end;

function TCityScene.TakeSvg(Mark: Integer): string;
begin
  if FStaticSvg <> nil then Result := FStaticSvg.Take(Mark) else Result := '';
end;

{ Cuts every static part for each palette, then the light sprites. }
procedure TCityScene.RenderStatic;
var
  M, I, K, Mk, N: Integer;
  Cut: TPainter;
  L, A, Blur: TBGRABitmap;
  Pl: TPal;
  X, Y, WX, WY, X1, X2, Y1, Y2, Top, R: Single;
  Q: TPointF;
  C, SkyAtSun: TBGRAPixel;
  Pts: array of TPointF;
  Px: PBGRAPixel;

  { a new part: the accumulator is cleared and the SVG mark set }
  procedure Begin_;
  begin
    A.FillTransparent;
    Cut.FLayerTop := 0;
    Cut.TargetBand(0, FHeight);
    if FStaticSvg <> nil then Mk := FStaticSvg.Mark else Mk := 0;
  end;

  { one paper sheet: drawn on the work layer, then stacked with its shadow }
  procedure Sheet;
  begin
    Cut.BeginLayer;
  end;

  procedure Stack(Depth: Single);
  begin
    Cut.CompositeLayer(A, 0, Depth);
    Cut.TargetBand(0, FHeight);
  end;

begin
  Mk := 0;
  Cut := FCutter;
  L := Cut.FLayer;
  A := FAcc;
  for M := 0 to 2 do
  begin
    Pl := FPal[M];
    RandSeed := 4242;

    { sky: 7 wavy paper bands from the top colour to the horizon colour, the sun
      (or moon) with 3 paper halo rings }
    Begin_;
    Cut.DPoly(A, [PointF(0, 0), PointF(FWidth, 0), PointF(FWidth, FHeight), PointF(0, FHeight)], Pl.SkyTop);
    for K := 0 to 6 do
    begin
      Sheet;
      N := Ceil((FVisR - FVisL + 80) / 16) + 1;
      SetLength(Pts, N + 2);
      for I := 0 to N - 1 do
      begin
        X := FVisL - 40 + I * 16;
        Y := 40 + K * 82 + 10 * Sin(X * 0.004 * (1 + K * 0.3) + K * 1.7) + 5 * Sin(X * 0.011 + K);
        Pts[I] := P(X, Y);
      end;
      Pts[N] := P(FVisR + 40, DesignH + 40);
      Pts[N + 1] := P(FVisL - 40, DesignH + 40);
      C := Mix(Pl.SkyTop, Pl.SkyBot, (K + 1) / 7);
      if M = 2 then C := Mix(C, Pl.Glow, Max(0, (K - 3) / 3) * 0.55);  // city glow at the horizon
      Cut.DPoly(L, Pts, C);
      Stack(0.3);
    end;
    SkyAtSun := Mix(Pl.SkyTop, Pl.SkyBot, EnsureRange((Pl.SunY - 40) / 574 + 0.1, 0, 1));
    Q := P(Pl.SunX, Pl.SunY);
    if Pl.SunHidden then
    begin
      // overcast: two sheets of scalloped low cloud across the top
      for K := 0 to 1 do
      begin
        Sheet;
        C := Mix(Pl.CloudShade, Pl.CloudLit, 0.15 + K * 0.45);
        Cut.Box(L, FVisL - 60, -60, FVisR + 60, 40 + K * 55, C);
        X := Floor((FVisL - 60) / 55) * 55;
        I := 0;
        while X < FVisR + 60 do
        begin
          Cut.DEllipse(L, P(X, 0).X, P(0, 40 + K * 55 + 6 * Hash01(I + K * 50)).Y, S(42 + 22 * Hash01(I * 3 + K)),
            S(24 + 10 * Hash01(I * 5 + K)), C);
          X := X + 55;
          Inc(I);
        end;
        Stack(0.45);
      end;
      Grain(A);
      Cut.Glow(A, Pl.SunX, Pl.SunY, 200, WithAlpha(Pl.Glow, IfThen(M = 2, 30, 40)));
    end
    else
    begin
    for K := 2 downto 0 do
    begin
      Sheet;
      R := Pl.SunR * (1.45 + K * 0.7);
      Cut.DEllipse(L, Q.X, Q.Y, S(R), S(R), Mix(SkyAtSun, Pl.SunC, 0.22 + (2 - K) * 0.16));
      Stack(0.22);
    end;
    Sheet;
    Cut.DEllipse(L, Q.X, Q.Y, S(Pl.SunR), S(Pl.SunR), Pl.SunC);
    if Pl.Moon then
    begin
      Cut.DEllipse(L, Q.X - S(6), Q.Y - S(4), S(5), S(5), Darken(Pl.SunC, 0.88));
      Cut.DEllipse(L, Q.X + S(7), Q.Y + S(6), S(3.5), S(3.5), Darken(Pl.SunC, 0.88));
      Cut.DEllipse(L, Q.X + S(4), Q.Y - S(9), S(2.5), S(2.5), Darken(Pl.SunC, 0.9));
    end;
    Stack(0.4);
    Grain(A);
    // soft light from the sun / moon over the paper
    Cut.Glow(A, Pl.SunX, Pl.SunY, Pl.SunR * 7, WithAlpha(Pl.Glow, IfThen(M = 2, 45, 80)));
    end;
    FSky[M] := TBGRABitmap(A.Duplicate);
    FSky[M].LoadFromBitmapIfNeeded;
    FSvgSky[M] := TakeSvg(Mk);

    { far city: two paper rows }
    Begin_;
    for K := 0 to 1 do
    begin
      Sheet;
      for I := 0 to High(FFarRects) do
        if Odd(I) = (K = 1) then
          with FFarRects[I] do
            if (Right > FVisL - 20) and (Left < FVisR + 20) then
              if K = 0 then
                Cut.Box(L, Left, Top - 14, Right, Bottom, Mix(Pl.Far, Pl.Haze, 0.45))
              else
                Cut.Box(L, Left, Top, Right, Bottom, Pl.Far);
      Stack(0.25 + K * 0.08);
    end;
    Grain(A);
    FFar[M] := Crop(380, FarBaseY + 30, FFarPos);
    FSvgFar[M] := TakeSvg(Mk);

    { Manhattan: back row, landmarks, front row - three sheets }
    Begin_;
    Sheet;
    for I := 0 to High(FBuildings) do
      if FBuildings[I].Back and (FBuildings[I].X + FBuildings[I].W > FVisL - 30) and (FBuildings[I].X < FVisR + 30) then
        Cut.CutBuilding(L, FBuildings[I], Pl);
    Stack(0.45);
    Sheet;
    Cut.CutLandmarks(L, Pl);
    Stack(0.6);
    Sheet;
    for I := 0 to High(FBuildings) do
      if not FBuildings[I].Back and (FBuildings[I].X + FBuildings[I].W > FVisL - 30) and (FBuildings[I].X < FVisR + 30) then
        Cut.CutBuilding(L, FBuildings[I], Pl);
    Stack(0.75);
    Grain(A);
    FCity[M] := Crop(60, CityBaseY + 46, FCityPos);
    FSvgCity[M] := TakeSvg(Mk);

    { river: the far water sheet (the wave strips are live) }
    Begin_;
    Cut.Box(A, FVisL - 20, CityBaseY - 2, FVisR + 20, RiverBotY, Pl.Water1);
    Grain(A);
    FRiver[M] := Crop(CityBaseY - 4, RiverBotY + 2, FRiverPos);
    FSvgRiver[M] := TakeSvg(Mk);

    { Statue of Liberty: her own sheet, in front of the waves }
    Begin_;
    Sheet;
    Cut.CutLiberty(L, Pl);
    Stack(0.6);
    Grain(A);
    FLib[M] := Crop(LibertyBase - 135 * LibertyK, LibertyBase + 30, FLibPos);
    FSvgLib[M] := TakeSvg(Mk);

    { bridge: cables sheet, then towers and deck }
    Begin_;
    Sheet;
    Cut.CutBridge(L, Pl, 0);
    Stack(0.25);
    Sheet;
    Cut.CutBridge(L, Pl, 1);
    Stack(0.8);
    Grain(A);
    FBridge[M] := Crop(TowerTopY - 12, RiverBotY + 24, FBridgePos);
    FSvgBridge[M] := TakeSvg(Mk);

    { street: the road, then the far side sheet and the near sidewalk sheet }
    Begin_;
    Cut.CutStreet(A, Pl, 0);
    Sheet;
    Cut.CutStreet(L, Pl, 1);
    Stack(0.7);
    Sheet;
    Cut.CutStreet(L, Pl, 2);
    Stack(0.5);
    Grain(A);
    FStreet[M] := Crop(RiverBotY - 140, DesignH + 2, FStreetPos);
    FSvgStreet[M] := TakeSvg(Mk);
  end;

  { window lights: lit cells of every building + far city dots, then a bloom
    (a blurred copy under the sharp windows) so lit towers glow into the night }
  RandSeed := 777;
  Begin_;
  SetLength(FFlicker, 0);
  SetLength(FRefl, 0);
  for I := 0 to High(FFarRects) do
    with FFarRects[I] do
      if (Right > FVisL - 20) and (Left < FVisR + 20) then
      begin
        X := Left + 2;
        while X < Right - 2 do
        begin
          Y := Top + 3;
          while Y < FarBaseY - 2 do
          begin
            if Random < 0.28 then Cut.DRect(A, X, Y, X + 1.6, Y + 1.6, WinLit[Random(5)]);
            Y := Y + 5;
          end;
          X := X + 4;
        end;
      end;
  for I := 0 to High(FBuildings) do
    with FBuildings[I] do
    begin
      if (X + W < FVisL - 30) or (X > FVisR + 30) then Continue;
      Top := BaseY - H;
      for K := 0 to Tiers do
      begin
        if K = 0 then
        begin
          X1 := X; X2 := X + W; Y1 := BaseY - H; Y2 := BaseY;
        end
        else
        begin
          X1 := X + TierInset[K - 1] * W; X2 := X + W - TierInset[K - 1] * W;
          Y2 := Top; Y1 := Top - TierH[K - 1]; Top := Y1;
        end;
        if K = 0 then Top := Y1;
        WY := Y1 + 6;
        while WY + 5 < Y2 - 3 do
        begin
          if Random < 0.85 then  // whole floors tend to be on or off together
          begin
            WX := X1 + 3;
            while WX + 4 < X2 - 2 do
            begin
              if Random < LitProb then
              begin
                C := WinLit[Random(5)];
                if Back then C := Darken(C, 0.85);
                if Tone = 3 then Cut.DRect(A, WX, WY, WX + 5, WY + 6, C)
                else if Random < 0.25 then
                  Cut.DRect(A, WX, WY + 2, WX + 4, WY + 5, C)  // blind half down
                else
                  Cut.DRect(A, WX, WY, WX + 4, WY + 5, C);
                if (Random < 0.012) and (Length(FFlicker) < 90) then
                begin
                  SetLength(FFlicker, Length(FFlicker) + 1);
                  FFlicker[High(FFlicker)].X := WX; FFlicker[High(FFlicker)].Y := WY;
                  FFlicker[High(FFlicker)].W := IfThen(Tone = 3, 5, 4);
                  FFlicker[High(FFlicker)].H := IfThen(Tone = 3, 6, 5);
                  FFlicker[High(FFlicker)].Rate := RandRange(0.15, 0.6);
                  FFlicker[High(FFlicker)].Phase := RandRange(0, 6);
                  if Random < 0.3 then
                    FFlicker[High(FFlicker)].C := Hex('#9FC8FF')  // a TV
                  else
                    FFlicker[High(FFlicker)].C := C;
                end;
                if (Random < 0.004) and (Y2 > CityBaseY - 60) then
                begin
                  SetLength(FRefl, Length(FRefl) + 1);
                  FRefl[High(FRefl)].X := WX + 2;
                  FRefl[High(FRefl)].C := C;
                  FRefl[High(FRefl)].Strength := RandRange(0.5, 0.9);
                end;
              end;
              WX := WX + 7;
            end;
          end;
          WY := WY + 9;
        end;
      end;
    end;
  for I := 0 to 11 do
    for K := 0 to 22 do
      if Random < 0.6 then
        Cut.DRect(A, 560 + 6 + I * 6.5, CityBaseY - 205 + K * 9, 560 + 9 + I * 6.5, CityBaseY - 200 + K * 9,
          WinLit[Random(5)]);
  for I := 0 to 9 do
    for K := 0 to 26 do
      if Random < 0.55 then
        Cut.DRect(A, 760 + 6 + I * 7, CityBaseY - 244 + K * 9, 760 + 9 + I * 7, CityBaseY - 239 + K * 9,
          WinLit[Random(5)]);
  Blur := TBGRABitmap(A.FilterBlurRadial(Max(2, Round(S(5))), rbFast));
  try
    for I := 0 to Blur.Height - 1 do
    begin
      Px := RowPtr(Blur, I);
      for K := 0 to Blur.Width - 1 do
      begin
        Px^.alpha := Px^.alpha * 5 div 4;
        if Px^.alpha > 160 then Px^.alpha := 160;
        Inc(Px);
      end;
    end;
    BlendBitmap(Blur, 0, 0, A);
    A.PutImage(0, 0, Blur, dmSet);
  finally
    Blur.Free;
  end;
  FWinLights := Crop(60, CityBaseY + 6, FWinPos);
  FSvgWinLights := TakeSvg(Mk);

  { bridge lights: bulbs along the cables and deck lamps }
  Begin_;
  X := Floor((FVisL - 60) / 22) * 22;
  while X < FVisR + 60 do
  begin
    Cut.Glow(A, X, CableY(X), 6, WithAlpha(Hex('#FFE6A8'), 230));
    Cut.DEllipse(A, P(X, CableY(X)).X, P(X, CableY(X)).Y, S(1.4), S(1.4), Hex('#FFF6DA'));
    if Round(X / 22) mod 3 = 0 then
    begin
      Cut.Glow(A, X, DeckY - 9, 11, WithAlpha(Hex('#FFD9A0'), 210));
      SetLength(FRefl, Length(FRefl) + 1);
      FRefl[High(FRefl)].X := X;
      FRefl[High(FRefl)].C := Hex('#FFE6A8');
      FRefl[High(FRefl)].Strength := 0.7;
    end;
    X := X + 22;
  end;
  FBridgeLights := Crop(TowerTopY - 12, DeckY + 14, FBridgeLPos);
  FSvgBridgeLights := TakeSvg(Mk);

  { street glow: lamp heads, light cones and pools on the sidewalk and road }
  Begin_;
  for I := 0 to High(FLamps) do
  begin
    X := FLamps[I];
    if (X < FVisL - 120) or (X > FVisR + 120) then Continue;
    Cut.DEllipseG(A, P(X + 24, RoadTopY + 4).X, P(X + 24, RoadTopY + 4).Y, S(105), S(30),
      MakeGrad(WithAlpha(Hex('#FFD9A0'), 85), WithAlpha(Hex('#FFD9A0'), 0), True,
      P(X + 24, RoadTopY + 4), P(X + 129, RoadTopY + 4)));
    SetLength(Pts, 4);
    Pts[0] := P(X + 16, WalkTopY - 118); Pts[1] := P(X + 32, WalkTopY - 118);
    Pts[2] := P(X + 80, RoadTopY + 10); Pts[3] := P(X - 32, RoadTopY + 10);
    Cut.DPolyG(A, Pts, MakeGrad(WithAlpha(Hex('#FFE0B0'), 60), WithAlpha(Hex('#FFE0B0'), 0), False,
      P(0, WalkTopY - 118), P(0, RoadTopY + 10)));
    Cut.Glow(A, X + 24, WalkTopY - 117, 30, WithAlpha(Hex('#FFD9A0'), 200));
    Cut.Glow(A, X + 24, WalkTopY - 117, 9, WithAlpha(Hex('#FFF6DA'), 255));
    Cut.DEllipse(A, P(X + 24, WalkTopY - 117).X, P(X + 24, WalkTopY - 117).Y, S(6), S(2.6), Hex('#FFFBEA'));
    if FSeason = 1 then  // the lamp mirrored in the wet road: a long streak
      Cut.DPolyG(A, [P(X + 14, RoadTopY + 2), P(X + 34, RoadTopY + 2), P(X + 30, RoadBotY), P(X + 18, RoadBotY)],
        MakeGrad(WithAlpha(Hex('#FFD9A0'), 110), WithAlpha(Hex('#FFD9A0'), 0), False,
        P(0, RoadTopY + 2), P(0, RoadBotY)));
    if FSeason = 2 then  // string lights on the bare trees
      for K := 0 to 13 do
      begin
        R := K * 2 * Pi / 14;
        Y := WalkTopY - 34 + Sin(R) * 13 - K * 0.6;
        C := WinLit[0];
        case K mod 4 of
          0: C := Hex('#FF4A3A');
          1: C := Hex('#4AE07A');
          2: C := Hex('#FFD04A');
          3: C := Hex('#5A9AFF');
        end;
        Cut.Glow(A, X + 105 + Cos(R) * 17, Y, 5, WithAlpha(C, 230));
        Cut.DEllipse(A, P(X + 105 + Cos(R) * 17, Y).X, P(0, Y).Y, S(1.3), S(1.3), Mix(C, Hex('#FFFFFF'), 0.5));
      end;
  end;
  FStreetGlow := Crop(WalkTopY - 160, RoadBotY + 6, FGlowPos);
  FSvgStreetGlow := TakeSvg(Mk);

  CutCloudSprites;

  { caption: a cream paper card }
  FCaption := TBGRABitmap.Create(Max(1, Round(S(440))), Max(1, Round(S(86))));
  FCaption.FillRoundRectAntialias(S(5), S(8), S(438), S(84), S(10), S(10), BGRA(0, 0, 0, 60));
  FCaption.FillRoundRectAntialias(S(1), S(1), S(430), S(76), S(10), S(10), BGRA(246, 238, 222, 240));
  FCaption.RoundRectAntialias(S(7), S(7), S(424), S(70), S(6), S(6), BGRA(196, 70, 50, 200), Max(1, S(1.2)));
  FCaption.FontName := 'Segoe UI';
  FCaption.FontQuality := fqFineAntialiasing;
  FCaption.FontStyle := [fsBold];
  FCaption.FontHeight := Max(8, Round(S(28)));
  FCaption.TextOut(S(215), S(9), 'NEW YORK PAPERCUT', BGRA(48, 40, 52), taCenter);
  FCaption.FontStyle := [];
  FCaption.FontHeight := Max(7, Round(S(15)));
  FCaption.TextOut(S(215), S(46), 'M D N A  time of day     1 2 3  season     I info',
    BGRA(150, 60, 44), taCenter);
  FCaption.LoadFromBitmapIfNeeded;
  FCaption.InvalidateBitmap;
  if FStaticSvg <> nil then
  begin
    Mk := FStaticSvg.Mark;
    FStaticSvg.RoundRect(S(5), S(8), S(438), S(84), S(10), S(10), BGRA(0, 0, 0, 60));
    FStaticSvg.RoundRect(S(1), S(1), S(430), S(76), S(10), S(10), BGRA(246, 238, 222, 240));
    FStaticSvg.RoundRect(S(7), S(7), S(424), S(70), S(6), S(6), BGRA(196, 70, 50, 200), Max(1, S(1.2)));
    FStaticSvg.Text(S(215), S(9), 'NEW YORK PAPERCUT', 'Segoe UI', Max(8, Round(S(28))), True,
      BGRA(48, 40, 52), True);
    FStaticSvg.Text(S(215), S(46), 'M D N A  time of day     1 2 3  season     I info', 'Segoe UI',
      Max(7, Round(S(15))), False, BGRA(150, 60, 44), True);
    FSvgCaption := FStaticSvg.Take(Mk);
  end;
end;

{ Paper grain: a fine fixed noise (per pixel hash, two scales) on every cut
  pixel, so flat colours read as paper. Pixel coordinates, so it does not swim. }
procedure TCityScene.Grain(B: TBGRABitmap);
var
  X, Y, V, T: Integer;
  H, H2: LongWord;
  Px: PBGRAPixel;
begin
  for Y := 0 to B.Height - 1 do
  begin
    Px := RowPtr(B, Y);
    for X := 0 to B.Width - 1 do
    begin
      if Px^.alpha > 0 then
      begin
        H := (LongWord(X) * 73856093) xor (LongWord(Y) * 19349663);
        H := H * 2654435761;
        H := H xor (H shr 15);
        H2 := (LongWord(X div 3) * 83492791) xor (LongWord(Y div 2) * 2971215073);
        H2 := H2 * 2246822519;
        H2 := H2 xor (H2 shr 13);
        V := Integer((H shr 8) and 7) - 4 + Integer((H2 shr 9) and 7) - 3;
        T := Px^.red + V;
        if T < 0 then T := 0 else if T > 255 then T := 255;
        Px^.red := T;
        T := Px^.green + V;
        if T < 0 then T := 0 else if T > 255 then T := 255;
        Px^.green := T;
        T := Px^.blue + V;
        if T < 0 then T := 0 else if T > 255 then T := 255;
        Px^.blue := T;
      end;
      Inc(Px);
    end;
  end;
  B.InvalidateBitmap;
end;

{ Cloud sprites for each palette: shaded puffs, blurred, flat faded base. }
procedure TCityScene.CutCloudSprites;
var
  I, M, J, W, H, Mk: Integer;
  Spr: TBGRABitmap;
  Q: TPointF;
  R: Single;
  Cut: TPainter;
  Outer: string;

  procedure Origin(const Cl: TCloud);
  begin
    Cut.FOrgX := S(-Cl.MinX + 12);
    Cut.FOrgY := S(-Cl.MinY + 12);
  end;

begin
  Cut := FCutter;
  Cut.FLayerTop := 0;
  for I := 0 to High(FClouds) do
    with FClouds[I] do
    begin
      W := Min(FWidth, Ceil(S(MaxX - MinX + 44)));
      H := Min(FHeight, Ceil(S(MaxY - MinY + 44)));
      if (W < 4) or (H < 4) then Continue;
      for M := 0 to 2 do
      begin
        Spr := TBGRABitmap.Create(W, H);
        if FStaticSvg <> nil then Mk := FStaticSvg.Mark else Mk := 0;
        // back sheet: the shaded underside, a little lower and to the right
        Cut.BeginLayer;
        Origin(FClouds[I]);
        J := 0;
        while J + 2 <= High(Puffs) do
        begin
          R := Puffs[J + 2];
          Q := Cut.P(Puffs[J] + 8, Puffs[J + 1] + 6);
          Cut.DEllipse(Cut.FLayer, Q.X, Q.Y, S(R), S(R * 0.82), FPal[M].CloudShade);
          Inc(J, 3);
        end;
        Cut.CompositeLayer(Spr, 0, 0.35);
        // front sheet: the lit top
        Cut.BeginLayer;
        Origin(FClouds[I]);
        J := 0;
        while J + 2 <= High(Puffs) do
        begin
          R := Puffs[J + 2];
          Q := Cut.P(Puffs[J], Puffs[J + 1] - 2);
          Cut.DEllipse(Cut.FLayer, Q.X, Q.Y, S(R * 0.86), S(R * 0.72), FPal[M].CloudLit);
          Inc(J, 3);
        end;
        Cut.CompositeLayer(Spr, 0, 0.5);
        Grain(Spr);
        if M = 2 then Spr.ApplyGlobalOpacity(200);
        Spr.LoadFromBitmapIfNeeded;
        Sprite[M] := Spr;
        if FStaticSvg <> nil then
        begin
          if M = 2 then Outer := '<g opacity="0.78">' else Outer := '<g>';
          Svg[M] := Outer + LineEnding + FStaticSvg.Take(Mk) + '</g>';
        end;
      end;
    end;
  Cut.TargetBand(0, FHeight);
end;

{ ---------- time of day ---------- }

procedure TCityScene.SetMode(AMode: Integer);
begin
  AMode := EnsureRange(AMode, 0, 2);
  if (AMode = FTo) and (FBlend = 0) and (FFrom = FTo) then Exit;
  FFrom := CurrentMode;
  FTo := AMode;
  FBlend := 0;
  if FFrom = FTo then FBlend := 0;
  FAutoTimer := 0;
end;

procedure TCityScene.SetModeInstant(AMode: Integer);
begin
  FFrom := EnsureRange(AMode, 0, 2);
  FTo := FFrom;
  FBlend := 0;
end;

function TCityScene.CurrentMode: Integer;
begin
  if FBlend >= 0.5 then Result := FTo else Result := FFrom;
end;

function TCityScene.Night: Single;
begin
  Result := ModeNight[FFrom] + (ModeNight[FTo] - ModeNight[FFrom]) * FBlend;
end;

function TCityScene.Shade: Single;
begin
  Result := ModeShade[FFrom] + (ModeShade[FTo] - ModeShade[FFrom]) * FBlend;
end;

function TCityScene.SignalState: Integer;
var
  T: Single;
begin
  T := Frac(FTime / 16) * 16;
  if T < 7 then Result := 0
  else if T < 9 then Result := 1
  else Result := 2;
end;

{ Cars keep their distance and stop at the line while the signal is not green. }
procedure TCityScene.UpdateTraffic(DT: Single);
var
  I, J, Ahead: Integer;
  Front, Gap, Best, V, Target, StopX, D: Single;
  Dir: Integer;
  Red: Boolean;
begin
  Red := SignalState <> 0;
  for I := 0 to High(FCars) do
    with FCars[I] do
    begin
      if Lane = 0 then Dir := -1 else Dir := 1;
      Front := X + Dir * Len / 2;
      // nearest car ahead in the same lane
      Best := 1e9;
      Ahead := -1;
      for J := 0 to High(FCars) do
        if (J <> I) and (FCars[J].Lane = Lane) then
        begin
          Gap := Dir * (FCars[J].X - X) - (FCars[J].Len + Len) / 2;
          if (Dir * (FCars[J].X - X) > 0) and (Gap < Best) then
          begin
            Best := Gap;
            Ahead := J;
          end;
        end;
      Target := Cruise;
      if Ahead >= 0 then
        Target := Min(Target, Max(0, (Best - 14) * 1.6));
      // signal: stop line before the crosswalk in each direction
      if Lane = 1 then StopX := SignalX - 120 else StopX := SignalX + 12;
      D := Dir * (StopX - Front);
      if Red and (D > -2) and (D < 170) then
        Target := Min(Target, Max(0, (D - 2) * 1.5));
      V := Speed;
      Brake := (Target < V - 1) or (V < 4);  // slowing down or standing: brake lights
      if Target < V then V := Max(Target, V - 260 * DT) else V := Min(Target, V + 70 * DT);
      Speed := V;
      X := X + Dir * V * DT;
      // leave on one side, come back on the other (only if there is room)
      if (Dir > 0) and (X > FVisR + 260) then X := FVisL - 260 - Random(200)
      else if (Dir < 0) and (X < FVisL - 260) then X := FVisR + 260 + Random(200);
    end;
end;

procedure TCityScene.Update(DT: Single);
var
  I: Integer;
  X, Y: Single;
begin
  FTime := FTime + DT;
  if FSnap <> nil then
  begin
    FSnapFade := FSnapFade - DT / 1.4;
    if FSnapFade <= 0 then FreeAndNil(FSnap);
  end;
  // lightning in the rain: flash, dark, second flash, fade; a new bolt each time
  if FSeason = 1 then
  begin
    FFlashNext := FFlashNext - DT;
    if FFlashNext <= 0 then
    begin
      FFlashT := 0;
      FFlashNext := RandRange(5, 11);
      X := RandRange(FVisL + 120, FVisR - 120);
      Y := 20;
      SetLength(FBolt, 0);
      while Y < CityBaseY - 230 do
      begin
        SetLength(FBolt, Length(FBolt) + 1);
        FBolt[High(FBolt)] := PointF(X, Y);
        X := X + RandRange(-30, 30);
        Y := Y + RandRange(22, 42);
      end;
    end;
    FFlashT := FFlashT + DT;
    if FFlashT < 0.07 then FFlash := 1
    else if FFlashT < 0.13 then FFlash := 0.15
    else if FFlashT < 0.2 then FFlash := 0.85
    else FFlash := Max(0, 0.85 * (1 - (FFlashT - 0.2) / 0.4));
    FBoltOn := FFlashT < 0.3;
  end
  else
    FFlash := 0;
  if FTo <> FFrom then
  begin
    FBlend := FBlend + DT / Max(0.1, FadeSeconds);
    if FBlend >= 1 then
    begin
      FFrom := FTo;
      FBlend := 0;
    end;
  end;
  if FAuto then
  begin
    FAutoTimer := FAutoTimer + DT;
    if (FAutoTimer > AutoSeconds) and (FFrom = FTo) then
      SetMode((FTo + 1) mod 3);
  end;
  for I := 0 to High(FClouds) do
    with FClouds[I] do
    begin
      OX := OX + Speed * DT;
      if (Speed > 0) and (MinX + OX > FVisR + 20) then OX := FVisL - 20 - MaxX;
      if (Speed < 0) and (MaxX + OX < FVisL - 20) then OX := FVisR + 20 - MinX;
    end;
  UpdateTraffic(DT);
  for I := 0 to High(FBridgeCars) do
    with FBridgeCars[I] do
    begin
      X := X + Dir * Speed * DT;
      if (Dir > 0) and (X > FVisR + 40) then X := FVisL - 40 - Random(300);
      if (Dir < 0) and (X < FVisL - 40) then X := FVisR + 40 + Random(300);
    end;
  // the train: across, wait, again
  if FTrainWait > 0 then
  begin
    FTrainWait := FTrainWait - DT;
    if FTrainWait <= 0 then FTrainX := FVisL - 10;
  end
  else
  begin
    FTrainX := FTrainX + 130 * DT;
    if FTrainX - 6 * 44 > FVisR + 20 then
    begin
      FTrainWait := RandRange(4, 9);
      FTrainX := FVisL - 400;
    end;
  end;
  for I := 0 to High(FBoats) do
    with FBoats[I] do
    begin
      X := X + Speed * DT;
      if (Speed > 0) and (X > FVisR + 140) then X := FVisL - 140;
      if (Speed < 0) and (X < FVisL - 140) then X := FVisR + 140;
    end;
  // the plane
  if FPlaneWait > 0 then
  begin
    FPlaneWait := FPlaneWait - DT;
    if FPlaneWait <= 0 then
    begin
      FPlaneX := FVisR + 60;
      FPlaneY := RandRange(90, 220);
    end;
  end
  else
  begin
    FPlaneX := FPlaneX - 120 * DT;
    if FPlaneX < FVisL - 600 then FPlaneWait := RandRange(3, 8);
  end;
  for I := 0 to High(FBirds) do
    with FBirds[I] do
    begin
      X := X + VX * DT;
      Y := Y + Sin(FTime * 0.8 + Phase) * 6 * DT;
      Phase := Phase + DT * 9;
      if X > FVisR + 40 then X := FVisL - 40 - Random(200);
    end;
end;

procedure TCityScene.Prepare;
begin
  if FPendingSeason >= 0 then ApplySeason;
end;

procedure TCityScene.SetSeason(ASeason: Integer; AFade: Boolean);
begin
  FPendingSeason := EnsureRange(ASeason, 0, SeasonCount - 1);
  FPendingFade := AFade;
end;

{ Main thread, workers idle (called from Prepare): keep the current picture for
  the fade, then new palettes and a fresh cut of every static sheet. }
procedure TCityScene.ApplySeason;
var
  NewS: Integer;
  Snap: TBGRABitmap;
  Pt: TPainter;
begin
  NewS := FPendingSeason;
  FPendingSeason := -1;
  if NewS = FSeason then Exit;
  Snap := nil;
  if FPendingFade and (FWidth > 1) and (FSky[0] <> nil) then
  begin
    Snap := TBGRABitmap.Create(FWidth, FHeight);
    Pt := TPainter.Create(Self);
    try
      Pt.RenderBand(Snap, 0);
    finally
      Pt.Free;
    end;
  end;
  FSeason := NewS;
  MakePalettes;
  FFlashT := 10;
  FFlash := 0;
  if FWidth > 1 then Resize(FWidth, FHeight);
  FSnap := Snap;
  FSnapFade := 1;
end;

procedure TCityScene.CopyStateFrom(Src: TCityScene);
var
  I: Integer;
begin
  FTime := Src.FTime;
  FFrom := Src.FFrom;
  FTo := Src.FTo;
  FBlend := Src.FBlend;
  { the auto cycle carries over, so an "as shown" export records the changes too }
  FAuto := Src.FAuto;
  FAutoTimer := Src.FAutoTimer;
  AutoSeconds := Src.AutoSeconds;
  FadeSeconds := Src.FadeSeconds;
  FCars := Copy(Src.FCars);
  FBridgeCars := Copy(Src.FBridgeCars);
  FBoats := Copy(Src.FBoats);
  FBirds := Copy(Src.FBirds);
  FTrainX := Src.FTrainX;
  FTrainWait := Src.FTrainWait;
  FPlaneX := Src.FPlaneX;
  FPlaneY := Src.FPlaneY;
  FPlaneWait := Src.FPlaneWait;
  for I := 0 to Min(High(FClouds), High(Src.FClouds)) do
    FClouds[I].OX := Src.FClouds[I].OX;
  FFlash := Src.FFlash;
  FFlashT := Src.FFlashT;
  FFlashNext := Src.FFlashNext;
  FBolt := Copy(Src.FBolt);
  FBoltOn := Src.FBoltOn;
  if Src.FSeason <> FSeason then
  begin
    // the same season as the live view: new palettes and a fresh cut
    FSeason := Src.FSeason;
    MakePalettes;
    if FWidth > 1 then Resize(FWidth, FHeight);
  end;
end;

procedure TCityScene.RenderSvg(Svg: TSvgRecorder);
var
  Pt: TPainter;
begin
  Svg.AddDefsFrom(FStaticSvg);
  Pt := TPainter.Create(Self);
  try
    Pt.FSvg := Svg;
    Pt.FRaster := False;
    Pt.RenderBand(nil, 0);
  finally
    Pt.Free;
  end;
end;

{ ---------- developer information ---------- }

function TCityScene.SpriteCount: Integer;
begin
  Result := Length(FClouds) * 3;
end;

function TCityScene.SpriteBytes: Int64;
var
  I, M: Integer;
begin
  Result := 0;
  for I := 0 to High(FClouds) do
    for M := 0 to 2 do
      if FClouds[I].Sprite[M] <> nil then
        Inc(Result, Int64(FClouds[I].Sprite[M].NbPixels) * 4);
  if FCaption <> nil then Inc(Result, Int64(FCaption.NbPixels) * 4);
end;

function TCityScene.StaticBytes: Int64;
var
  M: Integer;

  procedure Add(B: TBGRABitmap);
  begin
    if B <> nil then Inc(Result, Int64(B.NbPixels) * 4);
  end;

begin
  Result := 0;
  for M := 0 to 2 do
  begin
    Add(FSky[M]); Add(FFar[M]); Add(FCity[M]); Add(FRiver[M]); Add(FBridge[M]); Add(FStreet[M]);
    Add(FLib[M]);
  end;
  Add(FWinLights); Add(FBridgeLights); Add(FStreetGlow); Add(FCutter.FLayer); Add(FAcc);
end;

function TCityScene.CarCount: Integer;
begin
  Result := Length(FCars);
end;

function TCityScene.WindowLightCount: Integer;
begin
  Result := Length(FFlicker);
end;

function TCityScene.DescribeParams: string;
var
  SL: TStringList;
  Id: TLayerId;
  M: Integer;

  function F(V: Single): string;
  begin
    Result := FormatFloat('0.##', V);
  end;

begin
  SL := TStringList.Create;
  try
    SL.Add('DESIGN SPACE');
    SL.Add(Format('  %d x %d design px (landscape); city base y %d, river to %d, bridge deck y %d,',
      [DesignW, DesignH, CityBaseY, RiverBotY, DeckY]));
    SL.Add(Format('  road %d..%d (centre line %d), traffic signal at x %d', [RoadTopY, RoadBotY,
      RoadMidY, SignalX]));
    SL.Add(Format('  window %d x %d, scale %s, offset (%s, %s), visible x %s .. %s',
      [FWidth, FHeight, FormatFloat('0.0000', FScale), F(FOffX), F(FOffY), F(FVisL), F(FVisR)]));
    SL.Add('');
    SL.Add(Format('SEASON  %s  (1 summer, 2 rainy, 3 winter)', [SeasonNames[FSeason]]));
    SL.Add('');
    SL.Add('TIME OF DAY');
    SL.Add(Format('  now: %s -> %s, blend %s, night amount %s, auto %s (%s s each), fade %s s',
      [ModeNames[FFrom], ModeNames[FTo], F(FBlend), F(Night), IfThen(FAuto, 'on', 'off'),
      F(AutoSeconds), F(FadeSeconds)]));
    for M := 0 to 2 do
      SL.Add(Format('  %-8s lights %s, body shade %s, sun/moon at (%s, %s)', [ModeNames[M],
        F(ModeNight[M]), F(ModeShade[M]), F(FPal[M].SunX), F(FPal[M].SunY)]));
    SL.Add('  every static part is cut once per palette; a change fades the "to" set over');
    SL.Add('  the "from" set; lights are separate sprites faded in by the night amount');
    SL.Add('');
    SL.Add('LAYERS (back to front)');
    SL.Add('  Layer            Kind                  Notes');
    for Id := Low(TLayerId) to High(TLayerId) do
      SL.Add(Format('  %-16s %-21s %s', [LayerNames[Id], LayerKinds[Id], LayerNotes[Id]]));
    SL.Add('');
    SL.Add('CONTENT');
    SL.Add(Format('  buildings %d (2 rows) + Empire State, Chrysler, One WTC, crane, Liberty',
      [Length(FBuildings)]));
    SL.Add(Format('  roof beacons %d, flickering windows %d, reflection columns %d, stars %d',
      [Length(FBeacons), Length(FFlicker), Length(FRefl), Length(FStars)]));
    SL.Add(Format('  clouds %d, lamps %d, road vehicles %d, bridge cars %d, boats %d, birds %d',
      [Length(FClouds), Length(FLamps), Length(FCars), Length(FBridgeCars), Length(FBoats), Length(FBirds)]));
    SL.Add('  traffic signal: green 7 s, yellow 2 s, red 7 s; cars brake for the stop line and');
    SL.Add('  keep a gap to the car ahead; subway train every 4-9 s; plane every 3-8 s');
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

initialization
  WinLit[0] := Hex('#FFD58A');
  WinLit[1] := Hex('#FFF1D0');
  WinLit[2] := Hex('#CFE6FF');
  WinLit[3] := Hex('#FFC266');
  WinLit[4] := Hex('#FFE7B0');
end.
