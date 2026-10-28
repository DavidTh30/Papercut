unit uMountainScene;

{ Chinese Mountain Ranges Papercut - Guilin-style karst peaks as layered cut
  paper, animated, at morning, day or night, in four seasons.

  Back to front: paper sky bands with sun / moon rings, stars, paper clouds, far
  peaks, mist, middle peaks, mist, the karst pillars with a pagoda on top and a
  waterfall down a cliff, the Li river (paper wave strips, mist on the water,
  reflections), bamboo rafts with fishermen and cormorants and a sampan, the
  near bank with framing peaks, pines, maples, bamboo, a village and a pavilion,
  red lanterns, chimney smoke, cranes / geese, weather, caption.

  Paper look (shared with New York Town Papercut): flat paper colours, a fine
  grain on every cut sheet, a soft shadow under every sheet. Static sheets have
  the shadow baked in when the window size changes; moving paper (boats,
  lanterns, birds) casts it live per band. Lights ADD light.

  Time of day: morning / day / night palettes, crossfaded. Seasons: SUMMER (jade
  green, fireflies and sky lanterns at night), RAINY (grey, heavy mist, rain,
  ripples, lightning, a fuller waterfall), AUTUMN (red / orange / gold trees,
  falling leaves, geese, a big moon and sky lanterns at night) and WINTER (snow
  caps on every peak, snowy trees and roofs, a frozen waterfall, ice floes,
  snowfall). A season re-cuts the sheets; the old picture fades out on top.

  TMountainScene holds the state and every read-only resource; TPainter renders
  one band, one painter per worker thread; in vector mode it writes SVG. }

{$mode objfpc}{$H+}
{$INLINE ON}

interface

uses
  Classes, SysUtils, StrUtils, Math, Graphics, BGRABitmap, BGRABitmapTypes,
  BGRAGradientScanner, uRenderPool, uSvgRecorder;

const
  DesignW = 1600;
  DesignH = 900;
  Base0 = 545;       // foot of the far peaks
  Base1 = 592;       // middle peaks
  Base2 = 652;       // karst pillars, standing in the river
  RiverTop = 652;
  RiverBot = 800;
  GroundY = 800;     // the near bank
  PagodaX = 1140;
  WaterfallX = 474;
  PavilionX = 360;
  SpriteKinds = 1;   // kept for the frame renderer
  MaxDepth = 0.9;    // deepest live paper shadow (band work layer margins)
  ModeCount = 3;
  ModeNames: array[0..2] of string = ('Morning', 'Day', 'Night');
  ModeNight: array[0..2] of Single = (0.3, 0, 1);     // how much the lights are on
  ModeShade: array[0..2] of Single = (0.88, 1, 0.45); // brightness of lit bodies
  SeasonCount = 4;
  SeasonNames: array[0..3] of string = ('Summer', 'Rainy', 'Autumn', 'Winter');

type
  TLayerId = (lySky, lyStars, lyClouds, lyFarPeaks, lyMist, lyMidPeaks, lyPeaks, lyTempleLights,
    lyRiver, lyReflections, lyWaterfall, lyBoats, lyForeground, lyVillageLights, lyLanterns,
    lySmoke, lyBirds, lyWeather, lyCaption);

const
  LayerNames: array[TLayerId] of string = ('Sky', 'Stars', 'Clouds', 'Far peaks', 'Mist',
    'Middle peaks', 'Karst peaks', 'Temple lights', 'River', 'Reflections', 'Waterfall', 'Boats',
    'Foreground', 'Village lights', 'Lanterns', 'Smoke', 'Birds', 'Weather', 'Caption');
  LayerKinds: array[TLayerId] of string = ('paper x3', 'vector', 'paper sprites x3', 'paper x3',
    'live strips', 'paper x3', 'paper x3', 'light sprite+live', 'paper x3+strips', 'light', 'live',
    'live paper+light', 'paper x3', 'light sprite', 'live paper+light', 'live', 'live paper', 'live',
    'static');
  { paper shadow depth of each layer }
  LayerDepth: array[TLayerId] of Single = (0.3, 0, 0.5, 0.3, 0, 0.4, 0.6, 0, 0.35, 0, 0, 0.5, 0.85,
    0, 0.4, 0, 0.5, 0, 0);
  LayerNotes: array[TLayerId] of string = (
    '7 wavy paper bands, paper rings round the sun / moon (overcast sheets when rainy)',
    '220 stars twinkling at night (not when it rains)',
    '6 two-sheet paper clouds drifting both ways',
    'Farthest karst range, hazy, mist at its foot (sheet 0.3)',
    'Paper mist strips drifting at three heights: behind the middle range, behind the pillars, on the river',
    'Middle range with a sunlit flank on every peak (sheet 0.4)',
    'Karst pillars rising from the river: lit flanks, ridges, shrubs, the 7-tier pagoda (sheet 0.6)',
    'Pagoda windows lit at night, lanterns swinging under the eaves, a glow on the top',
    'Water + 4 paper wave strips rolling both ways; ice floes in winter',
    'Moon path and pagoda lights on the water at night, sun glitter by day',
    'Falling streaks and splash down the cliff; frozen in winter, fuller in the rain',
    'Two bamboo rafts (fisherman, cormorants, a fire basket at night), a sampan with a lantern',
    'Near bank and framing peaks with pines, maples, bamboo, village and pavilion (sheet 0.85)',
    'Village windows and the pavilion glowing at night',
    'Red paper lanterns swinging at the doors and in the pavilion, lit at night',
    'Chimney smoke rising and drifting with the wind',
    'Cranes flying (not in the rain); a V of geese in autumn',
    'Fireflies + sky lanterns (summer night), rain + lightning, falling leaves, snowfall',
    'Title card with hotkeys');

  PaletteNames: array[0..19] of string = ('Day sky top', 'Day horizon', 'Morning sky top',
    'Morning horizon', 'Night sky top', 'Night horizon', 'Sun', 'Moon', 'Far peaks (day)',
    'Middle peaks (day)', 'Karst pillars (day)', 'Near bank (day)', 'Jade water', 'Pine',
    'Autumn red', 'Autumn gold', 'Lantern red', 'Wall', 'Roof', 'Snow');
  PaletteHex: array[0..19] of string = ('#3C86D0', '#CFE8F2', '#6C8CC8', '#F6C49A', '#070B1C',
    '#22305A', '#FFF4CC', '#F4F0DC', '#B4D2CC', '#88B8AC', '#5A9484', '#2F6250', '#5AA0B8',
    '#2C5A3C', '#C8462A', '#E8A830', '#C8302A', '#F2EEE6', '#3E4448', '#F2F6FA');

type
  TPal = record
    SkyTop, SkyBot, Glow, SunC, Haze, Water1, Water2, Foliage, Foliage2, Pine, Trunk, Wall, Roof,
    Rock, Snow, CloudLit, CloudShade, Lit: TBGRAPixel;
    Range: array[0..3] of TBGRAPixel;
    SunX, SunY, SunR, MistK, Shade: Single;
    Moon, SunHidden: Boolean;
  end;

  TPeak = record
    C, W, H: Single;
  end;

  TRange = record
    Base: Single;
    Peaks: array of TPeak;
    Order: array of Integer;   // drawing order: low peaks first
  end;

  TCloud = record
    Puffs: array of Single;  // x, y, r triples
    MinX, MaxX, MinY, MaxY, OX, Speed: Single;
    Sprite: array[0..2] of TBGRABitmap;
    Svg: array[0..2] of string;
  end;

  TBoat = record
    X, Y, Speed, Size: Single;
    Kind: Integer;           // 0 bamboo raft with a fisherman, 1 sampan
  end;

  TBird = record
    X, Y, VX, Size, Phase: Single;
  end;

  TStar = record
    X, Y, R, Phase: Single;
  end;

  THouse = record
    X, W, Base: Single;
    Chimney: Boolean;
  end;

  TLantern = record
    X, Y, Len, Size, Phase: Single;  // anchor, string length
  end;

  TMountainScene = class;

  TDrawProc = procedure(B: TBGRABitmap) of object;

  { TPainter: renders frame rows into a band bitmap. One per worker thread. }

  TPainter = class
  private
    FScene: TMountainScene;
    FLayer: TBGRABitmap;
    FOrgX, FOrgY: Single;
    FTargetH: Integer;
    FPts: array of TPointF;
    FSvg: TSvgRecorder;
    FRaster: Boolean;
    FLayerTop: Integer;
    FRowA, FRowB: Integer;
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
    procedure DRect(B: TBGRABitmap; X1, Y1, X2, Y2: Single; C: TBGRAPixel);
    procedure DRadialRect(B: TBGRABitmap; X1, Y1, X2, Y2: Integer; C1, C2: TBGRAPixel;
      Ctr, Edge: TPointF);
    procedure Glow(B: TBGRABitmap; X, Y, R: Single; C: TBGRAPixel);
    procedure HDash(B: TBGRABitmap; X, Y, Len, Thick: Single; C: TBGRAPixel);
    procedure RainStreak(B: TBGRABitmap; X, Y, DX, Len, Thick: Single; C: TBGRAPixel);
    procedure EdgeFill(B: TBGRABitmap; const Edge: array of TPointF; ShiftX, Off, Thick, YBot: Single;
      C: TBGRAPixel);
    procedure Box(B: TBGRABitmap; X1, Y1, X2, Y2: Single; C: TBGRAPixel);
    procedure Ell(B: TBGRABitmap; X, Y, RX, RY: Single; C: TBGRAPixel);  // design coords
    procedure Ln(B: TBGRABitmap; X1, Y1, X2, Y2, W: Single; C: TBGRAPixel);  // design coords
    { static cut (per palette) }
    procedure CutRange(B: TBGRABitmap; R: Integer; const Pal: TPal);
    procedure CutPine(B: TBGRABitmap; X, Y, H: Single; const Pal: TPal);
    procedure CutTree(B: TBGRABitmap; X, Y, H: Single; const Pal: TPal; Seed: Integer);
    procedure CutBamboo(B: TBGRABitmap; X, Y, H: Single; const Pal: TPal);
    procedure CutPagoda(B: TBGRABitmap; const Pal: TPal);
    procedure CutHouse(B: TBGRABitmap; const Hs: THouse; const Pal: TPal);
    procedure CutPavilion(B: TBGRABitmap; const Pal: TPal);
    procedure CutForeground(B: TBGRABitmap; const Pal: TPal);
    { live parts }
    procedure DrawStars(Dest: TBGRABitmap);
    procedure DrawClouds(Dest: TBGRABitmap);
    procedure DrawMist(Dest: TBGRABitmap; Level: Integer);
    procedure DrawTempleLights(Dest: TBGRABitmap);
    procedure DrawWaves(Dest: TBGRABitmap);
    procedure DrawReflections(Dest: TBGRABitmap);
    procedure DrawWaterfall(Dest: TBGRABitmap);
    procedure DrawBoats(Dest: TBGRABitmap);
    procedure DrawLanterns(Dest: TBGRABitmap);
    procedure DrawSmoke(Dest: TBGRABitmap);
    procedure DrawBirds(Dest: TBGRABitmap);
    procedure DrawWeather(Dest: TBGRABitmap);
  public
    LayerMs: array[TLayerId] of Double;
    constructor Create(AScene: TMountainScene);
    destructor Destroy; override;
    procedure ResetStats;
    procedure RenderBand(Dest: TBGRABitmap; ATop: Integer);
  end;

  { TMountainScene }

  TMountainScene = class
  private
    FWidth, FHeight: Integer;
    FVisL, FVisR: Single;
    FScale, FOffX, FOffY: Single;
    FPal: array[0..2] of TPal;
    { static sheets per palette, cropped to their rows }
    FSky, FR0, FR1, FR2, FRiver, FNear: array[0..2] of TBGRABitmap;
    FR0Pos, FR1Pos, FR2Pos, FRiverPos, FNearPos: TPoint;
    FSvgSky, FSvgR0, FSvgR1, FSvgR2, FSvgRiver, FSvgNear: array[0..2] of string;
    { night lights, faded in by the night amount }
    FTempleLit, FVillageLit: TBGRABitmap;
    FTempleLitPos, FVillageLitPos: TPoint;
    FSvgTempleLit, FSvgVillageLit: string;
    FCaption: TBGRABitmap;
    FSvgCaption: string;
    FAcc: TBGRABitmap;
    FCutter: TPainter;
    FRecordSvg: Boolean;
    FStaticSvg: TSvgRecorder;
    { content }
    FRanges: array[0..3] of TRange;
    FStars: array of TStar;
    FClouds: array of TCloud;
    FBoats: array of TBoat;
    FBirds: array of TBird;
    FHouses: array of THouse;
    FLanterns: array of TLantern;
    FChimneys: array of TPointF;
    FTierY, FTierW, FTierH: array[0..6] of Single;  // pagoda tiers: base y, half width, height
    FPagodaBase, FWfTop: Single;
    FGooseX, FGooseY: Single;
    FTime: Single;
    { time of day }
    FFrom, FTo: Integer;
    FBlend: Single;
    FAuto: Boolean;
    FAutoTimer: Single;
    FShowCaption: Boolean;
    { season }
    FSeason, FPendingSeason: Integer;
    FPendingFade: Boolean;
    FSnap: TBGRABitmap;
    FSnapFade: Single;
    FFlash, FFlashT, FFlashNext: Single;
    FBolt: array of TPointF;
    FBoltOn: Boolean;
    function P(X, Y: Single): TPointF;
    function S(V: Single): Single;
    procedure MakePalettes;
    procedure SeasonTint(var Pl: TPal; M: Integer);
    procedure Generate;
    procedure AddCloud(Index: Integer; CX, CY, W, H, Speed: Single);
    procedure FreeResources;
    function Crop(Y0, Y1: Single; out Pos: TPoint): TBGRABitmap;
    function TakeSvg(Mark: Integer): string;
    procedure RenderStatic;
    procedure Grain(B: TBGRABitmap);
    procedure CutCloudSprites;
    procedure ApplySeason;
    function RangeY(R: Integer; X: Single): Single;
  public
    LayerOn: array[TLayerId] of Boolean;
    TransparentBack: Boolean;
    StaticMs: Double;
    StaticCount: Integer;
    AutoSeconds: Single;
    FadeSeconds: Single;
    constructor Create;
    destructor Destroy; override;
    procedure Resize(AWidth, AHeight: Integer);
    function SpriteJobCount: Integer;
    procedure SpriteJob(AIndex, AWorker: Integer);
    procedure Update(DT: Single);
    procedure Prepare;
    procedure CopyStateFrom(Src: TMountainScene);
    procedure RenderSvg(Svg: TSvgRecorder);
    procedure SetMode(AMode: Integer);
    procedure SetModeInstant(AMode: Integer);
    procedure SetSeason(ASeason: Integer; AFade: Boolean = True);
    function Night: Single;
    function Shade: Single;
    function CurrentMode: Integer;
    function SpriteCount: Integer;
    function SpriteBytes: Int64;
    function StaticBytes: Int64;
    function DescribeParams: string;
    function PeakCount: Integer;
    function LanternCount: Integer;
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

function RowPtr(B: TBGRABitmap; Y: Integer): PBGRAPixel; inline;
begin
  if B.LineOrder = riloTopToBottom then
    Result := B.Data + Y * B.Width
  else
    Result := B.Data + (B.Height - 1 - Y) * B.Width;
end;

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
{ TPainter: the paper engine (shared with New York Town Papercut)         }
{ ====================================================================== }

constructor TPainter.Create(AScene: TMountainScene);
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

procedure TPainter.Box(B: TBGRABitmap; X1, Y1, X2, Y2: Single; C: TBGRAPixel);
begin
  DPoly(B, [P(X1, Y1), P(X2, Y1), P(X2, Y2), P(X1, Y2)], C);
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

procedure TMountainScene.AddCloud(Index: Integer; CX, CY, W, H, Speed: Single);
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

function TMountainScene.Crop(Y0, Y1: Single; out Pos: TPoint): TBGRABitmap;
var
  A, B: Integer;
begin
  A := EnsureRange(Floor(P(0, Y0).Y), 0, FHeight - 1);
  B := EnsureRange(Ceil(P(0, Y1).Y), A + 1, FHeight);
  Pos := Point(0, A);
  Result := TBGRABitmap(FAcc.GetPart(Rect(0, A, FWidth, B)));
  Result.LoadFromBitmapIfNeeded;
end;

function TMountainScene.TakeSvg(Mark: Integer): string;
begin
  if FStaticSvg <> nil then Result := FStaticSvg.Take(Mark) else Result := '';
end;

procedure TMountainScene.Grain(B: TBGRABitmap);
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

procedure TMountainScene.CutCloudSprites;
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

procedure TMountainScene.SetMode(AMode: Integer);
begin
  AMode := EnsureRange(AMode, 0, 2);
  if (AMode = FTo) and (FBlend = 0) and (FFrom = FTo) then Exit;
  FFrom := CurrentMode;
  FTo := AMode;
  FBlend := 0;
  if FFrom = FTo then FBlend := 0;
  FAutoTimer := 0;
end;

procedure TMountainScene.SetModeInstant(AMode: Integer);
begin
  FFrom := EnsureRange(AMode, 0, 2);
  FTo := FFrom;
  FBlend := 0;
end;

function TMountainScene.CurrentMode: Integer;
begin
  if FBlend >= 0.5 then Result := FTo else Result := FFrom;
end;

function TMountainScene.Night: Single;
begin
  Result := ModeNight[FFrom] + (ModeNight[FTo] - ModeNight[FFrom]) * FBlend;
end;

function TMountainScene.Shade: Single;
begin
  Result := ModeShade[FFrom] + (ModeShade[FTo] - ModeShade[FFrom]) * FBlend;
end;

function TMountainScene.SpriteJobCount: Integer;
begin
  Result := 0;
end;

procedure TMountainScene.SpriteJob(AIndex, AWorker: Integer);
begin
end;

procedure TMountainScene.Prepare;
begin
  if FPendingSeason >= 0 then ApplySeason;
end;

procedure TMountainScene.SetSeason(ASeason: Integer; AFade: Boolean);
begin
  FPendingSeason := EnsureRange(ASeason, 0, SeasonCount - 1);
  FPendingFade := AFade;
end;

procedure TMountainScene.ApplySeason;
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

procedure TMountainScene.RenderSvg(Svg: TSvgRecorder);
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


{ karst peak profile: rounded top, steep sides; U in -1..1 }
function PeakF(U: Single): Single;
begin
  U := Abs(U);
  if U >= 1 then Result := 0
  else Result := Power(1 - Power(U, 2.4), 0.55);
end;

{ ====================================================================== }
{ TPainter: extra helpers                                                 }
{ ====================================================================== }

procedure TPainter.Ell(B: TBGRABitmap; X, Y, RX, RY: Single; C: TBGRAPixel);
var
  Q: TPointF;
begin
  Q := P(X, Y);
  DEllipse(B, Q.X, Q.Y, S(RX), S(RY), C);
end;

procedure TPainter.Ln(B: TBGRABitmap; X1, Y1, X2, Y2, W: Single; C: TBGRAPixel);
var
  A, Z: TPointF;
begin
  A := P(X1, Y1);
  Z := P(X2, Y2);
  DLine(B, A.X, A.Y, Z.X, Z.Y, C, Max(0.5, S(W)));
end;

{ ---------- static cut ---------- }

{ One range: a ground band, then every peak (low ones first, so a taller
  neighbour covers them) with its sunlit flank, ridge lines, shrubs on the top
  of the near ranges and a snow cap in winter; mist gathers at the foot. }
procedure TPainter.CutRange(B: TBGRABitmap; R: Integer; const Pal: TPal);
var
  I, J, K, Side: Integer;
  Base, U, X, Y, T: Single;
  Col, Lit, Dark, Veg: TBGRAPixel;
  Pts: array of TPointF;
  Sc: TMountainScene;
begin
  Sc := FScene;
  Base := Sc.FRanges[R].Base;
  Col := Pal.Range[R];
  Lit := Mix(Col, Pal.Lit, 0.16 + 0.05 * R);
  Dark := Darken(Col, 0.78);
  if Pal.SunX < 800 then Side := -1 else Side := 1;
  // ground band (for the bank: a gently waving ground line down to the bottom)
  if R < 3 then
    Box(B, Sc.FVisL - 40, Base - 6, Sc.FVisR + 40, Base + 70, Col)
  else
  begin
    SetLength(Pts, 0);
    X := Sc.FVisL - 40;
    while X <= Sc.FVisR + 48 do
    begin
      SetLength(Pts, Length(Pts) + 1);
      Pts[High(Pts)] := P(X, GroundY + 8 * Sin(X * 0.013) + 4 * Sin(X * 0.041));
      X := X + 8;
    end;
    SetLength(Pts, Length(Pts) + 2);
    Pts[High(Pts) - 1] := P(Sc.FVisR + 48, DesignH + 30);
    Pts[High(Pts)] := P(Sc.FVisL - 40, DesignH + 30);
    DPoly(B, Pts, Col);
    // the bank edge: a lighter lip of stones
    X := Floor((Sc.FVisL - 40) / 26) * 26;
    I := 0;
    while X < Sc.FVisR + 40 do
    begin
      Ell(B, X, GroundY + 8 * Sin(X * 0.013) + 4 * Sin(X * 0.041) + 2, 9 + 5 * Hash01(I), 3.5,
        Mix(Pal.Rock, Col, 0.3 + 0.3 * Hash01(I * 7)));
      X := X + 26;
      Inc(I);
    end;
  end;
  for K := 0 to High(Sc.FRanges[R].Order) do
    with Sc.FRanges[R].Peaks[Sc.FRanges[R].Order[K]] do
    begin
      if (C + W < Sc.FVisL - 40) or (C - W > Sc.FVisR + 40) then Continue;
      // body
      SetLength(Pts, 43);
      for J := 0 to 40 do
      begin
        U := -1 + J / 20;
        Pts[J] := P(C + U * W, Base - H * PeakF(U));
      end;
      Pts[41] := P(C + W, Base + 4);
      Pts[42] := P(C - W, Base + 4);
      DPoly(B, Pts, Col);
      // sunlit flank: a crescent along the edge facing the sun
      if R > 0 then
      begin
        SetLength(Pts, 42);
        for J := 0 to 20 do
        begin
          U := Side * J / 20;
          Pts[J] := P(C + U * W, Base - H * PeakF(U) + 0.5);
        end;
        for J := 20 downto 0 do
        begin
          T := J / 20;
          Pts[21 + (20 - J)] := P(C + Side * W * (0.16 + 0.52 * T), Base - H * PeakF(T) * 0.96 + 3);
        end;
        DPoly(B, Pts, Lit);
      end;
      // ridges
      if R >= 2 then
      begin
        Ln(B, C - Side * 0.12 * W, Base - H * 0.86, C - Side * 0.3 * W, Base - H * 0.32, 1.3, WithAlpha(Dark, 130));
        Ln(B, C + Side * 0.04 * W, Base - H * 0.7, C - Side * 0.06 * W, Base - H * 0.22, 1.1, WithAlpha(Dark, 110));
        Ln(B, C - Side * 0.45 * W, Base - H * 0.62, C - Side * 0.55 * W, Base - H * 0.2, 1.0, WithAlpha(Dark, 90));
      end;
      // shrubs on the tops of the near ranges
      if R >= 2 then
        for J := 0 to 6 do
        begin
          U := -0.62 + J * 0.2 + 0.08 * (Hash01(Round(C) + J) - 0.5);
          X := C + U * W;
          Y := Base - H * PeakF(U) + 3;
          case Sc.FSeason of
            2: if Odd(J) then Veg := Pal.Foliage else Veg := Pal.Foliage2;
            3: Veg := Pal.Snow;
          else
            Veg := Mix(Pal.Foliage, Col, 0.3);
          end;
          Ell(B, X, Y, 5 + 4 * Hash01(Round(C) * 3 + J), 3.6, Veg);
        end;
      // snow cap
      if (Sc.FSeason = 3) and (H > 90) then
      begin
        SetLength(Pts, 34);
        for J := 0 to 16 do
        begin
          U := -0.62 + J * 1.24 / 16;
          Pts[J] := P(C + U * W, Base - H * PeakF(U) - 0.6);
        end;
        for J := 16 downto 0 do
        begin
          U := -0.62 + J * 1.24 / 16;
          Pts[17 + (16 - J)] := P(C + U * W, Base - H * PeakF(U) + H * 0.13 * (1 - Sqr(U / 0.62)) +
            4 * Sin(J * 2.3 + C));
        end;
        DPoly(B, Pts, Pal.Snow);
      end;
    end;
  // mist gathering at the foot of the distant ranges
  if R < 3 then
    DPolyG(B, [P(Sc.FVisL - 40, Base - 110), P(Sc.FVisR + 40, Base - 110), P(Sc.FVisR + 40, Base + 8),
      P(Sc.FVisL - 40, Base + 8)], MakeGrad(WithAlpha(Pal.Haze, 0),
      WithAlpha(Pal.Haze, Round(Min(230, (150 - R * 25) * Pal.MistK))), False, P(0, Base - 110), P(0, Base)));
end;

{ A Chinese pine: a crooked trunk and flat pads of needles in tiers. }
procedure TPainter.CutPine(B: TBGRABitmap; X, Y, H: Single; const Pal: TPal);
var
  I: Integer;
  PX, PY, RX: Single;
begin
  DPolyLine(B, [P(X, Y), P(X + H * 0.08, Y - H * 0.5), P(X - H * 0.06, Y - H * 0.95)], Pal.Trunk,
    Max(0.8, S(H * 0.07)));
  for I := 0 to 2 do
  begin
    case I of
      0: begin PX := X + H * 0.14; PY := Y - H * 0.5; RX := H * 0.34; end;
      1: begin PX := X - H * 0.14; PY := Y - H * 0.72; RX := H * 0.3; end;
    else
      begin PX := X - H * 0.02; PY := Y - H * 0.95; RX := H * 0.24; end;
    end;
    Ell(B, PX, PY, RX, H * 0.09, Pal.Pine);
    Ell(B, PX - RX * 0.1, PY - H * 0.03, RX * 0.75, H * 0.05, Mix(Pal.Pine, Pal.Lit, 0.18));
    if FScene.FSeason = 3 then
      Ell(B, PX, PY - H * 0.05, RX * 0.85, H * 0.045, Pal.Snow);
  end;
end;

{ A broadleaf tree: green in summer, red / orange / gold in autumn, bare with
  snow in winter. }
procedure TPainter.CutTree(B: TBGRABitmap; X, Y, H: Single; const Pal: TPal; Seed: Integer);
var
  C1, C2: TBGRAPixel;
  I: Integer;
begin
  Ln(B, X, Y, X + H * 0.04, Y - H * 0.55, H * 0.07, Pal.Trunk);
  if FScene.FSeason = 3 then
  begin
    Ln(B, X + H * 0.03, Y - H * 0.45, X - H * 0.28, Y - H * 0.85, H * 0.035, Pal.Trunk);
    Ln(B, X + H * 0.03, Y - H * 0.5, X + H * 0.3, Y - H * 0.9, H * 0.035, Pal.Trunk);
    Ln(B, X + H * 0.04, Y - H * 0.55, X + H * 0.02, Y - H, H * 0.03, Pal.Trunk);
    Ell(B, X - H * 0.28, Y - H * 0.86, H * 0.1, H * 0.04, Pal.Snow);
    Ell(B, X + H * 0.3, Y - H * 0.91, H * 0.1, H * 0.04, Pal.Snow);
    Ell(B, X + H * 0.02, Y - H * 1.01, H * 0.08, H * 0.035, Pal.Snow);
    Exit;
  end;
  C1 := Pal.Foliage;
  C2 := Pal.Foliage2;
  if (FScene.FSeason = 2) and (Seed mod 3 = 1) then
  begin
    C1 := Pal.Foliage2;
    C2 := Mix(Pal.Foliage, Pal.Foliage2, 0.5);
  end;
  for I := 0 to 3 do
    Ell(B, X + H * (0.22 * Cos(I * 1.7 + Seed) - 0.02), Y - H * (0.72 + 0.12 * Sin(I * 2.1 + Seed)),
      H * (0.26 - I * 0.02), H * 0.2, C1);
  Ell(B, X - H * 0.08, Y - H * 0.85, H * 0.18, H * 0.13, C2);
end;

{ A clump of bamboo: thin jointed stalks and slender leaves. }
procedure TPainter.CutBamboo(B: TBGRABitmap; X, Y, H: Single; const Pal: TPal);
var
  I, J: Integer;
  SX, Lean, TX, TY: Single;
  Stalk, Leaf: TBGRAPixel;
begin
  Stalk := Mix(Pal.Foliage2, Pal.Trunk, 0.35);
  if FScene.FSeason = 3 then Leaf := Mix(Pal.Foliage2, Pal.Snow, 0.55) else Leaf := Pal.Foliage2;
  for I := 0 to 5 do
  begin
    SX := X + (I - 2.5) * 5;
    Lean := (I - 2.5) * 0.06;
    TX := SX + Lean * H;
    TY := Y - H * (0.8 + 0.2 * Hash01(I + Round(X)));
    Ln(B, SX, Y, TX, TY, 1.6, Stalk);
    for J := 1 to 4 do  // joints
      Ln(B, SX + (TX - SX) * J / 5 - 1.5, Y + (TY - Y) * J / 5, SX + (TX - SX) * J / 5 + 1.5,
        Y + (TY - Y) * J / 5, 0.9, Darken(Stalk, 0.7));
    for J := 0 to 3 do
      DPoly(B, [P(TX, TY + J * 8), P(TX + 13 * (1 - 2 * Ord(Odd(I + J))), TY + J * 8 + 4),
        P(TX, TY + J * 8 + 3)], Leaf);
  end;
end;

{ The 7-tier pagoda on the tallest karst pillar. }
procedure TPainter.CutPagoda(B: TBGRABitmap; const Pal: TPal);
var
  T: Integer;
  X, Y0, Wb, Hb: Single;
  Wall, Roof, Wood: TBGRAPixel;
  Sc: TMountainScene;
begin
  Sc := FScene;
  X := PagodaX;
  Wall := Mix(Pal.Wall, Pal.Rock, 0.25);
  Roof := Pal.Roof;
  Wood := Darken(Hex('#8A3A2A'), Pal.Shade);
  Box(B, X - 30, Sc.FPagodaBase - 4, X + 30, Sc.FPagodaBase + 3, Darken(Pal.Rock, 0.9));
  for T := 0 to 6 do
  begin
    Y0 := Sc.FTierY[T];
    Wb := Sc.FTierW[T];
    Hb := Sc.FTierH[T];
    Box(B, X - Wb * 0.55, Y0 - Hb, X + Wb * 0.55, Y0, Wall);
    Box(B, X - Wb * 0.55, Y0 - Hb, X - Wb * 0.42, Y0, Wood);
    Box(B, X + Wb * 0.42, Y0 - Hb, X + Wb * 0.55, Y0, Wood);
    Box(B, X - 2.5, Y0 - Hb * 0.8, X + 2.5, Y0 - Hb * 0.2, Darken(Wood, 0.6));  // window
    // eave with upturned tips
    DPoly(B, [P(X - Wb - 7, Y0 - Hb - 5), P(X - Wb + 1, Y0 - Hb - 1), P(X + Wb - 1, Y0 - Hb - 1),
      P(X + Wb + 7, Y0 - Hb - 5), P(X + Wb * 0.62, Y0 - Hb - 7.5), P(X - Wb * 0.62, Y0 - Hb - 7.5)], Roof);
    if Sc.FSeason = 3 then
      Box(B, X - Wb * 0.62, Y0 - Hb - 9, X + Wb * 0.62, Y0 - Hb - 6.8, Pal.Snow);
  end;
  Y0 := Sc.FTierY[6] - Sc.FTierH[6] - 7;
  Ln(B, X, Y0, X, Y0 - 20, 1.6, Darken(Roof, 1.3));
  Ell(B, X, Y0 - 8, 2.6, 2.6, Darken(Roof, 1.3));
  Ell(B, X, Y0 - 14, 2, 2, Darken(Roof, 1.3));
end;

{ A Huizhou-style house: white wall, stepped horse-head gables, a dark tiled
  roof, a red door, lattice windows. }
procedure TPainter.CutHouse(B: TBGRABitmap; const Hs: THouse; const Pal: TPal);
var
  X, W, Base: Single;
  Door: TBGRAPixel;
begin
  X := Hs.X;
  W := Hs.W;
  Base := Hs.Base;
  Door := Darken(Hex('#A8322A'), Pal.Shade);
  Box(B, X, Base - 34, X + W, Base, Pal.Wall);
  // roof between the gables
  DPoly(B, [P(X + 6, Base - 33), P(X + W - 6, Base - 33), P(X + W - 12, Base - 45), P(X + 12, Base - 45)], Pal.Roof);
  Box(B, X + 10, Base - 47, X + W - 10, Base - 44.5, Darken(Pal.Roof, 0.8));
  // stepped gables
  Box(B, X - 3, Base - 44, X + 9, Base - 30, Pal.Wall);
  Box(B, X - 5, Base - 46, X + 11, Base - 43, Pal.Roof);
  Box(B, X + W - 9, Base - 44, X + W + 3, Base - 30, Pal.Wall);
  Box(B, X + W - 11, Base - 46, X + W + 5, Base - 43, Pal.Roof);
  if Hs.Chimney then
  begin
    Box(B, X + W - 20, Base - 54, X + W - 13, Base - 42, Darken(Pal.Wall, 0.8));
    Box(B, X + W - 21, Base - 56, X + W - 12, Base - 53, Pal.Roof);
  end;
  if FScene.FSeason = 3 then
  begin
    Box(B, X + 11, Base - 49, X + W - 11, Base - 46, Pal.Snow);
    Box(B, X - 5, Base - 48.5, X + 11, Base - 46, Pal.Snow);
    Box(B, X + W - 11, Base - 48.5, X + W + 5, Base - 46, Pal.Snow);
  end;
  // eave line, door, windows
  Box(B, X, Base - 34, X + W, Base - 31, Darken(Pal.Wall, 0.75));
  Box(B, X + W / 2 - 5, Base - 18, X + W / 2 + 5, Base, Door);
  Box(B, X + W * 0.22 - 4, Base - 27, X + W * 0.22 + 4, Base - 18, Darken(Pal.Roof, 0.8));
  Box(B, X + W * 0.78 - 4, Base - 27, X + W * 0.78 + 4, Base - 18, Darken(Pal.Roof, 0.8));
  Ln(B, X + W * 0.22, Base - 27, X + W * 0.22, Base - 18, 0.7, Pal.Wall);
  Ln(B, X + W * 0.78, Base - 27, X + W * 0.78, Base - 18, 0.7, Pal.Wall);
end;

{ A hexagonal pavilion on a rock by the water. }
procedure TPainter.CutPavilion(B: TBGRABitmap; const Pal: TPal);
var
  X, Base: Single;
  I: Integer;
  Red: TBGRAPixel;
begin
  X := PavilionX;
  Base := FScene.RangeY(3, X);
  Red := Darken(Hex('#A8322A'), Pal.Shade);
  DPoly(B, [P(X - 46, Base + 6), P(X - 40, Base - 6), P(X - 18, Base - 10), P(X + 22, Base - 9),
    P(X + 44, Base - 4), P(X + 50, Base + 6)], Pal.Rock);
  Box(B, X - 36, Base - 14, X + 36, Base - 8, Mix(Pal.Rock, Pal.Wall, 0.4));
  for I := 0 to 3 do
    Box(B, X - 30 + I * 19, Base - 50, X - 26.5 + I * 19, Base - 14, Red);
  Box(B, X - 32, Base - 30, X + 32, Base - 28, Red);  // railing
  DPoly(B, [P(X - 52, Base - 46), P(X - 40, Base - 51), P(X + 40, Base - 51), P(X + 52, Base - 46),
    P(X + 32, Base - 62), P(X + 6, Base - 80), P(X - 6, Base - 80), P(X - 32, Base - 62)], Pal.Roof);
  if FScene.FSeason = 3 then
    DPoly(B, [P(X - 34, Base - 62), P(X - 6, Base - 81), P(X + 6, Base - 81), P(X + 34, Base - 62),
      P(X + 20, Base - 64), P(X, Base - 76), P(X - 20, Base - 64)], Pal.Snow);
  Ln(B, X, Base - 80, X, Base - 90, 1.6, Pal.Roof);
  Ell(B, X, Base - 90, 2.4, 2.4, Pal.Roof);
end;

{ The near bank: ground and framing peaks, pines on the slopes, trees and
  bamboo on the bank, the village and the pavilion. }
procedure TPainter.CutForeground(B: TBGRABitmap; const Pal: TPal);
var
  Sc: TMountainScene;
  X, Y: Single;
  I: Integer;
begin
  Sc := FScene;
  CutRange(B, 3, Pal);
  // pines clinging to the framing peaks
  X := -190;
  I := 0;
  while X < Sc.FVisR + 260 do
  begin
    Y := Sc.RangeY(3, X);
    if (Y < GroundY - 25) and (X > Sc.FVisL - 60) then
      CutPine(B, X, Y + 6, 30 + 28 * Hash01(I * 13), Pal);
    X := X + 30 + 16 * Hash01(I * 7);
    if (X > 300) and (X < 1300) then X := 1300;
    Inc(I);
  end;
  // trees and bamboo on the bank (the village and the pavilion keep their room)
  X := 440;
  I := 0;
  while X < 980 do
  begin
    Y := Sc.RangeY(3, X) + 4;
    case I mod 3 of
      0: CutTree(B, X, Y, 64 + 20 * Hash01(I), Pal, I);
      1: CutPine(B, X, Y, 58 + 20 * Hash01(I * 3), Pal);
    else
      CutBamboo(B, X, Y, 70, Pal);
    end;
    X := X + 70 + 30 * Hash01(I * 5);
    Inc(I);
  end;
  // the bank in front: rocks with a lit top, grass tufts, and per season
  // flowers, fallen leaves or snow drifts
  for I := 0 to 70 do
  begin
    X := Sc.FVisL - 20 + Hash01(I * 3 + 1) * (Sc.FVisR - Sc.FVisL + 40);
    Y := GroundY + 18 + Hash01(I * 3 + 2) * (DesignH - GroundY - 10);
    if Y < Sc.RangeY(3, X) + 8 then Continue;
    if I mod 7 = 0 then
    begin
      Ell(B, X, Y, 14 + 10 * Hash01(I), 7 + 3 * Hash01(I * 5), Darken(Pal.Rock, 0.85));
      Ell(B, X - 2, Y - 3, 10 + 7 * Hash01(I), 3.5, Mix(Pal.Rock, Pal.Lit, 0.25));
      Continue;
    end;
    case Sc.FSeason of
      3: Ell(B, X, Y, 12 + 10 * Hash01(I * 7), 3, Mix(Pal.Snow, Pal.Range[3], 0.15));
    else
      begin
        DPoly(B, [P(X - 6, Y), P(X - 4, Y - 9), P(X - 1, Y), P(X + 1, Y - 12), P(X + 3, Y), P(X + 6, Y - 8),
          P(X + 7, Y)], Mix(Pal.Range[3], Pal.Foliage2, 0.45));
        if (Sc.FSeason = 0) and (I mod 3 = 0) then
        begin
          Ell(B, X - 3, Y - 10, 2.2, 2.2, Darken(Hex('#F0D040'), Pal.Shade));
          Ell(B, X + 3, Y - 8, 2, 2, Darken(Hex('#E86A8A'), Pal.Shade));
        end;
        if Sc.FSeason = 2 then
        begin
          Ell(B, X + 9, Y + 2, 3, 1.6, Pal.Foliage);
          Ell(B, X - 10, Y + 3, 2.6, 1.4, Pal.Foliage2);
        end;
      end;
    end;
  end;
  CutBamboo(B, 268, Sc.RangeY(3, 268) + 4, 62, Pal);
  CutTree(B, 1318, Sc.RangeY(3, 1318) + 4, 70, Pal, 7);
  for I := 0 to High(Sc.FHouses) do
    CutHouse(B, Sc.FHouses[I], Pal);
  CutPavilion(B, Pal);
end;

{ ---------- live parts ---------- }

procedure TPainter.DrawStars(Dest: TBGRABitmap);
var
  I, A: Integer;
  N: Single;
  Q: TPointF;
begin
  N := FScene.Night;
  if (N < 0.05) or (FScene.FSeason = 1) then Exit;
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

{ Paper mist: two translucent strips per level with wavy tops, drifting
  sideways at different speeds. Heavier in the morning and in the rain. }
procedure TPainter.DrawMist(Dest: TBGRABitmap; Level: Integer);
var
  Sc: TMountainScene;
  K, I, N: Integer;
  X, X0, Y, Base, T, Thick, MK: Single;
  Edge: array of TPointF;
  C: TBGRAPixel;
begin
  Sc := FScene;
  case Level of
    0: Base := Base0 - 26;
    1: Base := Base1 - 22;
  else
    Base := RiverTop - 16;
  end;
  if not RowsHit(Base - 20, Base + 60) then Exit;
  MK := Sc.FPal[Sc.FFrom].MistK + (Sc.FPal[Sc.FTo].MistK - Sc.FPal[Sc.FFrom].MistK) * Sc.FBlend;
  C := Mix(Sc.FPal[Sc.FFrom].Haze, Sc.FPal[Sc.FTo].Haze, Sc.FBlend);
  X0 := Sc.FVisL - 40;
  N := Ceil((Sc.FVisR - X0 + 40) / 16) + 1;
  SetLength(Edge, N);
  for K := 0 to 1 do
  begin
    T := Sc.FTime * (0.05 + 0.03 * K + 0.02 * Level) * (1 - 2 * Ord(Odd(K + Level)));
    Thick := 22 + 12 * K + 6 * Level;
    for I := 0 to N - 1 do
    begin
      X := X0 + I * 16;
      Y := Base + K * 10 + 9 * Sin(X * 0.006 + T + K * 1.7 + Level) + 5 * Sin(X * 0.017 - T * 1.6 + K * 2);
      Edge[I] := P(X, Y);
    end;
    EdgeFill(Dest, Edge, 0, 0, S(Thick), 0, WithAlpha(C, Round(Min(220, (78 - 26 * K) * MK))));
  end;
end;

{ Pagoda lights at night: the window sprite is drawn by RenderBand; here the
  little lanterns under every eave tip swing, and the top glows. }
procedure TPainter.DrawTempleLights(Dest: TBGRABitmap);
var
  Sc: TMountainScene;
  T, I: Integer;
  N, X, Y, Sw: Single;
  Red: TBGRAPixel;
begin
  Sc := FScene;
  if not RowsHit(Sc.FTierY[6] - 40, Sc.FPagodaBase + 10) then Exit;
  N := Sc.Night;
  Red := Darken(Hex('#C8302A'), Sc.Shade);
  for T := 0 to 6 do
    for I := 0 to 1 do
    begin
      Sw := 1.2 * Sin(Sc.FTime * 1.6 + T + I * 2);
      X := PagodaX + (2 * I - 1) * (Sc.FTierW[T] + 6) + Sw;
      Y := Sc.FTierY[T] - Sc.FTierH[T] - 1;
      Ell(Dest, X, Y, 1.8, 2.2, Mix(Red, Hex('#FFB060'), N * 0.8));
      if N > 0.05 then
        Glow(Dest, X, Y, 7, WithAlpha(Hex('#FF9A40'), Round(230 * N)));
    end;
  if N > 0.05 then
    Glow(Dest, PagodaX, Sc.FTierY[6] - Sc.FTierH[6] - 20, 26, WithAlpha(Hex('#FFC870'), Round(90 * N)));
end;

{ The Li river: 4 paper wave strips (EdgeFill), ice floes in winter. }
procedure TPainter.DrawWaves(Dest: TBGRABitmap);
const
  Strips = 4;
var
  Sc: TMountainScene;
  K, I, N: Integer;
  X, X0, X1, Y, Base, Amp, T: Single;
  Edge: array of TPointF;
  W1, W2, C, Crest: TBGRAPixel;
begin
  Sc := FScene;
  if not RowsHit(RiverTop, RiverBot + 4) then Exit;
  W1 := Mix(Sc.FPal[Sc.FFrom].Water1, Sc.FPal[Sc.FTo].Water1, Sc.FBlend);
  W2 := Mix(Sc.FPal[Sc.FFrom].Water2, Sc.FPal[Sc.FTo].Water2, Sc.FBlend);
  X0 := Sc.FVisL - 30;
  X1 := Sc.FVisR + 30;
  N := Ceil((X1 - X0) / 10) + 1;
  SetLength(Edge, N);
  for K := 0 to Strips - 1 do
  begin
    Base := RiverTop + 18 + K * 32;
    if not RowsHit(Base - 12, RiverBot + 4) then Continue;
    Amp := 2.4 + K * 1.2;
    T := Sc.FTime * (0.6 + 0.25 * K);
    if Odd(K) then T := -T;
    for I := 0 to N - 1 do
    begin
      X := X0 + I * 10;
      Y := Base + Amp * Sin(X * (0.04 - K * 0.006) + T + K * 1.3) + Amp * 0.4 * Sin(X * 0.1 - T * 1.7 + K);
      Edge[I] := P(X, Y);
    end;
    if K = Strips - 1 then Y := RiverBot + 2 else Y := Base + 32 + 2.4 + (K + 1) * 1.2 * 1.4 + 3;
    C := Mix(W1, W2, 0.15 + 0.25 * K);
    Crest := Mix(C, BGRA(255, 255, 255), 0.26 * (1 - Sc.Night * 0.75));
    EdgeFill(Dest, Edge, S(1.5), -S(3.5), S(3.5), 0, BGRA(0, 0, 20, 45));
    EdgeFill(Dest, Edge, 0, 0, 0, P(0, Y).Y, C);
    EdgeFill(Dest, Edge, 0, 0, Max(0.8, S(1.4)), 0, Crest);
    if Sc.FSeason = 3 then
      for I := 0 to 4 do
      begin
        X := Sc.FVisL - 40 + PFrac(Hash01(K * 9 + I) + Sc.FTime * 0.006 * (1 + K * 0.3) *
          (1 - 2 * Ord(Odd(K)))) * (Sc.FVisR - Sc.FVisL + 80);
        Y := Base + Amp * Sin(X * (0.04 - K * 0.006) + T + K * 1.3) + 3;
        Ell(Dest, X + 1.5, Y + 1.5, 9 + 9 * Hash01(I * 3 + K), 2.6, BGRA(0, 0, 20, 50));
        Ell(Dest, X, Y, 9 + 9 * Hash01(I * 3 + K), 2.4, Mix(Hex('#F2F6FA'), C, 0.25 + 0.4 * Sc.Night));
      end;
  end;
end;

{ Moon path and the pagoda lights on the water at night, sun glitter by day. }
procedure TPainter.DrawReflections(Dest: TBGRABitmap);
var
  Sc: TMountainScene;
  J, A: Integer;
  N, Y, Wob, Len, Day, SunX: Single;
  Pl: TPal;
begin
  Sc := FScene;
  if not RowsHit(RiverTop, RiverBot) then Exit;
  N := Sc.Night;
  Pl := Sc.FPal[Sc.CurrentMode];
  if Pl.SunHidden then
  begin
    if N > 0.05 then  // only the pagoda shimmers through the rain
      for J := 0 to 14 do
      begin
        Y := RiverTop + 4 + J * 5;
        Wob := Sin(Sc.FTime * 1.6 + J * 0.9) * 3;
        HDash(Dest, PagodaX + Wob - 4, Y, 8, 1.4, WithAlpha(Hex('#FFB060'), Round(160 * N * (1 - J / 15))));
      end;
    Exit;
  end;
  if N > 0.05 then
  begin
    for J := 0 to 24 do  // moon path
    begin
      Y := RiverTop + 6 + J * 5.6;
      Wob := Sin(Sc.FTime * 1.8 + J * 1.3) * (4 + J * 0.6);
      Len := 6 + 12 * Hash01(J + Floor(Sc.FTime * 3));
      A := Round(200 * N * (0.35 + 0.65 * Abs(Sin(Sc.FTime * 3 + J))));
      HDash(Dest, Pl.SunX + Wob - Len / 2, Y, Len, 1.4, WithAlpha(Hex('#F4F0DC'), A));
    end;
    for J := 0 to 14 do  // pagoda
    begin
      Y := RiverTop + 4 + J * 5;
      Wob := Sin(Sc.FTime * 1.6 + J * 0.9) * 3;
      HDash(Dest, PagodaX + Wob - 4, Y, 8, 1.4, WithAlpha(Hex('#FFB060'), Round(170 * N * (1 - J / 15))));
    end;
  end;
  Day := 1 - N;
  if Day > 0.05 then
  begin
    SunX := Pl.SunX;
    for J := 0 to 36 do
    begin
      Y := RiverTop + 4 + J * 4;
      Wob := Sin(Sc.FTime * 2 + J * 1.3) * (6 + J * 0.8);
      Len := 6 + 12 * Hash01(J + Floor(Sc.FTime * 4));
      A := Round(190 * Day * (0.3 + 0.7 * Abs(Sin(Sc.FTime * 4 + J))));
      HDash(Dest, SunX + Wob - Len / 2, Y, Len, 1.2, WithAlpha(BGRA(255, 246, 220), A));
    end;
  end;
end;

{ The waterfall down the cliff: a pale column with streaks racing down and a
  splash at the foot; in winter frozen into icicles; fuller in the rain. }
procedure TPainter.DrawWaterfall(Dest: TBGRABitmap);
var
  Sc: TMountainScene;
  I, NStreaks: Integer;
  Top, Bot, X, Y, H1, Wd, K, Len: Single;
  W1, Col, Foam: TBGRAPixel;
begin
  Sc := FScene;
  Top := Sc.FWfTop;
  Bot := RiverTop + 6;
  if not RowsHit(Top - 4, Bot + 12) then Exit;
  W1 := Mix(Sc.FPal[Sc.FFrom].Water1, Sc.FPal[Sc.FTo].Water1, Sc.FBlend);
  K := Sc.Shade;
  if Sc.FSeason = 1 then Wd := 1.5 else Wd := 1;
  if Sc.FSeason = 3 then
  begin  // frozen
    Col := Mix(Darken(Hex('#E6F0F8'), K), W1, 0.25);
    DPoly(Dest, [P(WaterfallX - 3, Top), P(WaterfallX + 3, Top), P(WaterfallX + 8, Bot), P(WaterfallX - 8, Bot)], Col);
    for I := 0 to 6 do
      DPoly(Dest, [P(WaterfallX - 7 + I * 2.3, Bot - 30 + 8 * Hash01(I)), P(WaterfallX - 5.5 + I * 2.3, Bot - 30 + 8 * Hash01(I)),
        P(WaterfallX - 6.2 + I * 2.3, Bot - 8 + 6 * Hash01(I * 3))], Darken(Col, 0.86));
    Ell(Dest, WaterfallX, Bot + 2, 18, 4, Darken(Hex('#F2F6FA'), K));
    Exit;
  end;
  Col := WithAlpha(Mix(W1, Darken(Hex('#FFFFFF'), K), 0.55), 225);
  DPoly(Dest, [P(WaterfallX - 3 * Wd, Top), P(WaterfallX + 3 * Wd, Top), P(WaterfallX + 8 * Wd, Bot),
    P(WaterfallX - 8 * Wd, Bot)], Col);
  Foam := WithAlpha(Darken(Hex('#FFFFFF'), Max(0.6, K)), 190);
  NStreaks := Round(34 * Wd);
  for I := 0 to NStreaks - 1 do
  begin
    H1 := Hash01(I * 3 + 7);
    Len := 14 + 10 * Hash01(I * 3 + 8);
    Y := Top + PFrac(Hash01(I * 3 + 9) + Sc.FTime * (1.3 + 0.6 * H1)) * (Bot - Top);
    X := WaterfallX + (H1 - 0.5) * (6 + 10 * (Y - Top) / (Bot - Top)) * Wd;
    RainStreak(Dest, X, Y, 0, Min(Len, Bot - Y), 1.1, Foam);
  end;
  for I := 0 to 6 do  // splash
    Ell(Dest, WaterfallX + (I - 3) * 4 * Wd, Bot + 1 - 2 * Abs(Sin(Sc.FTime * 6 + I * 1.7)),
      (4 + 2 * Sin(Sc.FTime * 5 + I)) * Wd, 3, WithAlpha(Foam, 150));
  for I := 0 to 3 do
  begin
    K := PFrac(Sc.FTime / 1.4 + I / 4);
    HDash(Dest, WaterfallX - 10 - 26 * K, Bot + 4 + 6 * K, 20 + 52 * K, 1, WithAlpha(Foam, Round(150 * (1 - K))));
  end;
end;

{ Boats: bamboo rafts with a fisherman in a straw hat and two cormorants (a fire
  basket at night), and a sampan with a mat canopy and a lantern. }
procedure TPainter.DrawBoats(Dest: TBGRABitmap);
var
  Sc: TMountainScene;
  I, K: Integer;
  N, Sh, X, Y, Sz, Bob, D: Single;
  Bamboo, Robe, Hat, Bird, Hull, Mat: TBGRAPixel;

  procedure Lamp(LX, LY, R: Single; C: TBGRAPixel; Strength: Single);
  var
    J: Integer;
    WY, Wob, Len: Single;
  begin
    Glow(Dest, LX, LY, R, WithAlpha(C, Round(255 * Strength * N)));
    Glow(Dest, LX, LY, R * 3.5, WithAlpha(C, Round(70 * Strength * N)));
    WY := Y + 3 * Sz;
    for J := 1 to 8 do
    begin
      Wob := Sin(Sc.FTime * 3 + J * 1.9 + LX * 0.1) * 2.5;
      Len := 3 + 5 * Hash01(J * 13 + Round(LX));
      HDash(Dest, LX + Wob - Len / 2, WY + J * 3.4, Len, 1.4,
        WithAlpha(C, Round(200 * Strength * N * (1 - J / 9) * (0.5 + 0.5 * Sin(Sc.FTime * 5 + J)))));
    end;
  end;

begin
  Sc := FScene;
  if not RowsHit(RiverTop - 30, RiverBot + 30) then Exit;
  N := Sc.Night;
  Sh := Sc.Shade;
  Bamboo := Darken(Hex('#C2A060'), Sh);
  Robe := Darken(Hex('#2E4A6A'), Sh);
  Hat := Darken(Hex('#DCC488'), Sh);
  Bird := Darken(Hex('#1E1E22'), Max(0.6, Sh));
  Hull := Darken(Hex('#5A3A28'), Sh);
  Mat := Darken(Hex('#9A7646'), Sh);
  for I := 0 to High(Sc.FBoats) do
  begin
    X := Sc.FBoats[I].X;
    Sz := Sc.FBoats[I].Size;
    Bob := Sin(Sc.FTime * 1.3 + I * 2) * 1.2;
    Y := Sc.FBoats[I].Y + Bob;
    if Sc.FBoats[I].Speed >= 0 then D := 1 else D := -1;
    if (X < Sc.FVisL - 120) or (X > Sc.FVisR + 120) then Continue;
    if not RowsHit(Y - 60 * Sz, Y + 34 * Sz) then Continue;
    if (FPart = 1) and (N < 0.05) then Continue;
    if Sc.FBoats[I].Kind = 0 then
    begin
      if FPart = 0 then
      begin
        Box(Dest, X - 42 * Sz, Y - 3 * Sz, X + 42 * Sz, Y + 2 * Sz, Bamboo);
        for K := 0 to 6 do
          Ln(Dest, X - 40 * Sz + K * 13 * Sz, Y - 3 * Sz, X - 40 * Sz + K * 13 * Sz, Y + 2 * Sz, 0.8,
            Darken(Bamboo, 0.7));
        // fisherman: legs, robe, arms with the pole, straw hat
        Ln(Dest, X + 4 * Sz, Y - 3 * Sz, X + 6 * Sz, Y - 14 * Sz, 2.2 * Sz, Robe);
        Ln(Dest, X + 10 * Sz, Y - 3 * Sz, X + 8 * Sz, Y - 14 * Sz, 2.2 * Sz, Robe);
        DPoly(Dest, [P(X + 2 * Sz, Y - 13 * Sz), P(X + 12 * Sz, Y - 13 * Sz), P(X + 10 * Sz, Y - 28 * Sz),
          P(X + 4 * Sz, Y - 28 * Sz)], Robe);
        Ln(Dest, X + 7 * Sz - D * 6 * Sz, Y + 6 * Sz, X + 7 * Sz + D * 22 * Sz, Y - 46 * Sz, 1.1 * Sz,
          Darken(Bamboo, 0.6));
        Ell(Dest, X + 7 * Sz, Y - 31 * Sz, 2.6 * Sz, 2.8 * Sz, Darken(Hex('#C89A78'), Sh));
        DPoly(Dest, [P(X - 4 * Sz, Y - 31 * Sz), P(X + 7 * Sz, Y - 39 * Sz), P(X + 18 * Sz, Y - 31 * Sz)], Hat);
        // two cormorants on the raft
        for K := 0 to 1 do
        begin
          Ell(Dest, X - D * (20 + K * 14) * Sz, Y - 8 * Sz, 4.5 * Sz, 3 * Sz, Bird);
          Ln(Dest, X - D * (17 + K * 14) * Sz, Y - 9 * Sz, X - D * (15 + K * 14) * Sz, Y - 16 * Sz, 1.4 * Sz, Bird);
          DPoly(Dest, [P(X - D * (15 + K * 14) * Sz, Y - 17 * Sz), P(X - D * (11 + K * 14) * Sz, Y - 15.5 * Sz),
            P(X - D * (15 + K * 14) * Sz, Y - 15 * Sz)], Darken(Hex('#E8C040'), Sh));
        end;
        Ln(Dest, X + D * 36 * Sz, Y - 3 * Sz, X + D * 36 * Sz, Y - 22 * Sz, 1.2 * Sz, Darken(Bamboo, 0.6));
      end
      else
      begin
        // the fire basket at the bow, for night fishing
        Lamp(X + D * 36 * Sz, Y - 24 * Sz, 6 + 1.5 * Sin(Sc.FTime * 11 + I), Hex('#FF9A30'), 1);
        Glow(Dest, X + D * 36 * Sz, Y - 24 * Sz, 3, WithAlpha(Hex('#FFF0C0'), Round(255 * N)));
      end;
    end
    else
    begin
      if FPart = 0 then
      begin
        DPoly(Dest, [P(X - 50 * Sz, Y - 9 * Sz), P(X - 38 * Sz, Y + 3 * Sz), P(X + 38 * Sz, Y + 3 * Sz),
          P(X + 50 * Sz, Y - 9 * Sz), P(X + 40 * Sz, Y - 4 * Sz), P(X - 40 * Sz, Y - 4 * Sz)], Hull);
        DPoly(Dest, [P(X - 22 * Sz, Y - 4 * Sz), P(X - 22 * Sz, Y - 16 * Sz), P(X - 12 * Sz, Y - 24 * Sz),
          P(X + 12 * Sz, Y - 24 * Sz), P(X + 22 * Sz, Y - 16 * Sz), P(X + 22 * Sz, Y - 4 * Sz)], Mat);
        for K := 0 to 4 do
          Ln(Dest, X - 18 * Sz + K * 9 * Sz, Y - 4 * Sz, X - 18 * Sz + K * 9 * Sz, Y - 20 * Sz, 0.8, Darken(Mat, 0.75));
        Box(Dest, X - 14 * Sz, Y - 15 * Sz, X + 14 * Sz, Y - 7 * Sz, Mix(Darken(Hex('#3A2A20'), Sh), Hex('#FFD080'), N * 0.9));
        Ln(Dest, X - D * 46 * Sz, Y - 8 * Sz, X - D * 62 * Sz, Y + 8 * Sz, 1.4 * Sz, Darken(Bamboo, 0.6));  // oar
        Ln(Dest, X - D * 40 * Sz, Y - 6 * Sz, X - D * 40 * Sz, Y - 26 * Sz, 1 * Sz, Darken(Bamboo, 0.6));
        Ell(Dest, X - D * 40 * Sz, Y - 22 * Sz, 3 * Sz, 3.8 * Sz, Darken(Hex('#C8302A'), Sh));
      end
      else
      begin
        Lamp(X - D * 40 * Sz, Y - 22 * Sz, 6, Hex('#FF7A40'), 1);
        Glow(Dest, X, Y - 11 * Sz, 22 * Sz, WithAlpha(Hex('#FFD080'), Round(90 * N)));
      end;
    end;
  end;
end;

{ Red paper lanterns hanging at the village doors and in the pavilion: they
  swing (harder in the rain), glow at night and light the wall behind. }
procedure TPainter.DrawLanterns(Dest: TBGRABitmap);
var
  Sc: TMountainScene;
  I: Integer;
  N, Sh, A, CX, CY, Sz, Wind: Single;
  Red: TBGRAPixel;
begin
  Sc := FScene;
  N := Sc.Night;
  Sh := Sc.Shade;
  Red := Darken(Hex('#C8302A'), Sh);
  if Sc.FSeason = 1 then Wind := 0.35 else Wind := 0.16;
  for I := 0 to High(Sc.FLanterns) do
    with Sc.FLanterns[I] do
    begin
      if not RowsHit(Y - 4, Y + Len + 20) then Continue;
      A := Wind * Sin(Sc.FTime * 1.4 + Phase) + 0.05 * Sin(Sc.FTime * 3.1 + Phase * 2);
      Sz := Size;
      CX := X + Sin(A) * Len;
      CY := Y + Cos(A) * Len;
      if FPart = 0 then
      begin
        Ln(Dest, X, Y, CX, CY - 6 * Sz, 0.6, Darken(Hex('#2A2020'), Max(0.5, Sh)));
        Ell(Dest, CX, CY, 5 * Sz, 6 * Sz, Mix(Red, Hex('#FFB060'), N * 0.7));
        Box(Dest, CX - 3 * Sz, CY - 7 * Sz, CX + 3 * Sz, CY - 5 * Sz, Darken(Hex('#2A2020'), Max(0.5, Sh)));
        Box(Dest, CX - 3 * Sz, CY + 5 * Sz, CX + 3 * Sz, CY + 7 * Sz, Darken(Hex('#2A2020'), Max(0.5, Sh)));
        Ln(Dest, CX, CY + 7 * Sz, CX + Sin(A) * 3, CY + 13 * Sz, 1, Darken(Hex('#E8B030'), Sh));
      end
      else if N > 0.05 then
      begin
        Glow(Dest, CX, CY, 8 * Sz, WithAlpha(Hex('#FFC060'), Round(255 * N)));
        Glow(Dest, CX, CY, 30 * Sz, WithAlpha(Hex('#FF6A30'), Round(80 * N)));
      end;
    end;
end;

{ Chimney smoke: soft paper puffs rising and drifting with the wind. }
procedure TPainter.DrawSmoke(Dest: TBGRABitmap);
var
  Sc: TMountainScene;
  I, J, A: Integer;
  Age, X, Y, R, Wind, Amount: Single;
  C: TBGRAPixel;
begin
  Sc := FScene;
  if not RowsHit(GroundY - 220, GroundY - 40) then Exit;
  case Sc.FSeason of
    1: begin Wind := 1.8; Amount := 0.7; end;
    3: begin Wind := 0.8; Amount := 1.25; end;
  else
    begin Wind := 1; Amount := 1; end;
  end;
  C := Mix(Hex('#EEEEEA'), Hex('#5A6280'), Sc.Night);
  for I := 0 to High(Sc.FChimneys) do
    for J := 0 to 9 do
    begin
      Age := PFrac(Sc.FTime / 7 + J / 10 + I * 0.37);
      X := Sc.FChimneys[I].X + Age * 46 * Wind + 6 * Sin(Sc.FTime * 0.8 + J + I);
      Y := Sc.FChimneys[I].Y - Age * 140;
      R := 4 + Age * 16;
      A := Round((1 - Age) * 110 * Amount * (1 - 0.5 * Sc.Night));
      Ell(Dest, X, Y, R, R * 0.8, WithAlpha(C, A));
    end;
end;

{ Cranes gliding with slow wing beats; a V of geese in autumn. }
procedure TPainter.DrawBirds(Dest: TBGRABitmap);
var
  Sc: TMountainScene;
  I: Integer;
  Sz, Fl, X, Y, A: Single;
  White, Black, Grey: TBGRAPixel;
begin
  Sc := FScene;
  if (FPart <> 0) or (Sc.FSeason = 1) then Exit;
  A := 1 - Sc.Night;
  if A < 0.05 then Exit;
  White := WithAlpha(Darken(Hex('#F4F2EC'), Sc.Shade), Round(255 * A));
  Black := WithAlpha(Darken(Hex('#1E1E22'), Sc.Shade), Round(255 * A));
  for I := 0 to High(Sc.FBirds) do
    with Sc.FBirds[I] do
    begin
      if not RowsHit(Y - Size * 1.4, Y + Size) then Continue;
      Sz := Size;
      Fl := Sin(Phase);
      // trailing legs, body, neck and head with the red crown
      Ln(Dest, X - Sz * 0.5, Y + Sz * 0.05, X - Sz * 1.25, Y + Sz * 0.12, 0.9, Black);
      Ell(Dest, X, Y, Sz * 0.5, Sz * 0.14, White);
      Ln(Dest, X + Sz * 0.4, Y - Sz * 0.03, X + Sz * 0.95, Y - Sz * 0.08, Sz * 0.09, White);
      Ell(Dest, X + Sz * 1.0, Y - Sz * 0.09, Sz * 0.09, Sz * 0.07, Black);
      Ell(Dest, X + Sz * 1.0, Y - Sz * 0.15, Sz * 0.05, Sz * 0.04, WithAlpha(Darken(Hex('#E02A20'), Sc.Shade), Round(255 * A)));
      Ln(Dest, X + Sz * 1.06, Y - Sz * 0.08, X + Sz * 1.28, Y - Sz * 0.05, 0.8, Black);
      // wings: white with black tips, beating
      DPoly(Dest, [P(X - Sz * 0.25, Y - Sz * 0.05), P(X + Sz * 0.25, Y - Sz * 0.05),
        P(X + Sz * 0.05, Y - Sz * 0.9 * Fl), P(X - Sz * 0.45, Y - Sz * 0.85 * Fl)], White);
      DPoly(Dest, [P(X + Sz * 0.05, Y - Sz * 0.9 * Fl), P(X - Sz * 0.45, Y - Sz * 0.85 * Fl),
        P(X - Sz * 0.55, Y - Sz * 1.05 * Fl), P(X - Sz * 0.05, Y - Sz * 1.1 * Fl)], Black);
    end;
  if Sc.FSeason = 2 then
  begin
    Grey := WithAlpha(Darken(Hex('#3A3430'), Sc.Shade), Round(255 * A));
    for I := 0 to 8 do
    begin
      X := Sc.FGooseX - Abs(I - 4) * 20;
      Y := Sc.FGooseY + Abs(I - 4) * 11 * (1 - 2 * Ord(I < 4)) * 0 + Abs(I - 4) * 11;
      if not RowsHit(Y - 10, Y + 10) then Continue;
      Fl := Sin(Sc.FTime * 7 + I * 0.7) * 5;
      DPoly(Dest, [P(X - 7, Y + Fl * 0.6), P(X - 2, Y - 1), P(X + 4, Y), P(X, Y + 1.5)], Grey);
      DPoly(Dest, [P(X + 7, Y + Fl * 0.6 - 1), P(X + 2, Y - 1), P(X - 2, Y), P(X + 1, Y + 1.5)], Grey);
      Ln(Dest, X + 2, Y, X + 7, Y - 1, 1.4, Grey);
    end;
  end;
end;

{ Weather of the season; every drop / flake / leaf / light is a hash function of
  its index and the time: no state, exports replay it exactly.
    summer: fireflies over the bank and sky lanterns at night
    rainy:  rain, ripples on the river, lightning
    autumn: falling leaves (tumbling paper), sky lanterns at night
    winter: snowfall }
procedure TPainter.DrawWeather(Dest: TBGRABitmap);
const
  LeafCols: array[0..3] of string = ('#C8402A', '#E07A2A', '#E8B030', '#A8302A');
var
  Sc: TMountainScene;
  I, A: Integer;
  T, N, X, Y, Span, H1, H2, H3, Spd, Len, VX, P0, R, Sw, Ph, Ang, Bl: Single;
  C: TBGRAPixel;
  Pts: array of TPointF;
begin
  Sc := FScene;
  T := Sc.FTime;
  N := Sc.Night;
  Span := Sc.FVisR - Sc.FVisL + 160;
  case Sc.FSeason of
    1: begin
         VX := -90;
         C := Mix(BGRA(214, 224, 238), BGRA(170, 186, 214), N);
         for I := 0 to 449 do
         begin
           H1 := Hash01(I * 3 + 11);
           H2 := Hash01(I * 3 + 12);
           H3 := Hash01(I * 3 + 13);
           Spd := 520 + 280 * H3;
           Len := 12 + 16 * H3;
           P0 := PFrac(H2 + T * Spd / (DesignH + 80));
           Y := -40 + P0 * (DesignH + 80);
           if not RowsHit(Y, Y + Len) then Continue;
           X := Sc.FVisL - 80 + PFrac(H1 + VX * P0 * (DesignH + 80) / Spd / Span) * Span;
           RainStreak(Dest, X, Y, VX * Len / Spd, Len, 0.9 + 0.6 * H3, WithAlpha(C, Round(70 + 90 * H3)));
         end;
         C := Mix(BGRA(230, 238, 248), BGRA(160, 175, 205), N);
         for I := 0 to 49 do
         begin
           H2 := Hash01(I * 5 + 102);
           Ph := T / 0.9 + Hash01(I * 5 + 103);
           P0 := PFrac(Ph);
           X := Sc.FVisL + Hash01(I * 7 + Floor(Ph) * 131) * (Sc.FVisR - Sc.FVisL);
           Y := RiverTop + 8 + H2 * (RiverBot - RiverTop - 14);
           R := 1.5 + 7 * P0;
           A := Round(150 * (1 - P0));
           HDash(Dest, X - R, Y - R * 0.3, 2 * R, 0.9, WithAlpha(C, A));
           HDash(Dest, X - R * 0.8, Y + R * 0.3, 1.6 * R, 0.9, WithAlpha(C, A div 2));
         end;
         if Sc.FFlash > 0.01 then
         begin
           if Sc.FBoltOn and (Length(Sc.FBolt) > 1) and RowsHit(0, Base1) then
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
    3: begin
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
           Ell(Dest, X, Y, R, R, WithAlpha(C, Round(150 + 100 * H3)));
         end;
       end;
  end;
  if Sc.FSeason = 2 then  // falling leaves, tumbling
    for I := 0 to 139 do
    begin
      H1 := Hash01(I * 3 + 61);
      H2 := Hash01(I * 3 + 62);
      H3 := Hash01(I * 3 + 63);
      Spd := 30 + 40 * H3;
      R := 3.5 + 3.5 * H3;
      P0 := PFrac(H2 + T * Spd / (DesignH + 60));
      Y := -30 + P0 * (DesignH + 60);
      if not RowsHit(Y - R, Y + R) then Continue;
      Sw := Sin(T * (1.1 + H1) + I) * (18 + 26 * H3);
      X := Sc.FVisL - 80 + PFrac(H1 + T * (14 + 12 * H3) / Span) * Span + Sw;
      Ang := T * (1.5 + 2.5 * H1) + I;
      C := Darken(Hex(LeafCols[I mod 4]), Sc.Shade);
      DPoly(Dest, [P(X + Cos(Ang) * R, Y + Sin(Ang) * R * 0.6),
        P(X - Sin(Ang) * R * 0.45, Y + Cos(Ang) * R * 0.27),
        P(X - Cos(Ang) * R, Y - Sin(Ang) * R * 0.6),
        P(X + Sin(Ang) * R * 0.45, Y - Cos(Ang) * R * 0.27)], C);
    end;
  if (Sc.FSeason = 0) and (N > 0.05) then  // fireflies over the bank and the water
    for I := 0 to 69 do
    begin
      H1 := Hash01(I * 3 + 81);
      H2 := Hash01(I * 3 + 82);
      H3 := Hash01(I * 3 + 83);
      X := Sc.FVisL + H1 * (Sc.FVisR - Sc.FVisL) + 30 * Sin(T * (0.3 + 0.4 * H2) + I);
      Y := GroundY - 10 - H3 * 120 + 14 * Sin(T * (0.5 + 0.5 * H1) + I * 1.3);
      Bl := Sin(T * (1.5 + 2 * H2) + I * 2.1);
      if Bl <= 0 then Continue;
      Bl := Bl * Bl * Bl;
      Glow(Dest, X, Y, 6, WithAlpha(Hex('#D8FF6A'), Round(255 * N * Bl)));
    end;
  if (Sc.FSeason in [0, 2]) and (N > 0.35) then  // sky lanterns rising from the village
    for I := 0 to 15 do
    begin
      H1 := Hash01(I * 3 + 91);
      H2 := Hash01(I * 3 + 92);
      H3 := Hash01(I * 3 + 93);
      P0 := PFrac(T / (34 + 14 * H3) + H2);
      Y := GroundY - 60 - P0 * (GroundY - 20);
      X := 980 + 340 * H1 + (H2 - 0.5) * 300 * P0 + 10 * Sin(T * 0.6 + I);
      if not RowsHit(Y - 12, Y + 12) then Continue;
      R := (1 - 0.6 * P0) * (5 + 2 * H3);
      Bl := N * Min(1, (1 - P0) * 3);
      DPoly(Dest, [P(X - R * 0.7, Y - R), P(X + R * 0.7, Y - R), P(X + R * 0.9, Y + R), P(X - R * 0.9, Y + R)],
        WithAlpha(Mix(Hex('#FFB060'), Hex('#FFE6B0'), 0.5), Round(255 * Bl)));
      Glow(Dest, X, Y + R * 0.6, R * 1.8, WithAlpha(Hex('#FFD080'), Round(255 * Bl)));
      Glow(Dest, X, Y, R * 5, WithAlpha(Hex('#FF8A40'), Round(70 * Bl)));
    end;
end;

procedure TPainter.RenderBand(Dest: TBGRABitmap; ATop: Integer);
var
  Sc: TMountainScene;
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

  procedure Pair(const Arr: array of TBGRABitmap; const Pos: TPoint; const Svg: array of string);
  begin
    if FSvg <> nil then FSvg.Raw(Svg[M]);
    if not FRaster then Exit;
    BlendBitmap(Dest, Pos.X, Pos.Y - ATop, Arr[Sc.FFrom]);
    if (Sc.FFrom <> Sc.FTo) and (A > 0) then
      BlendBitmap(Dest, Pos.X, Pos.Y - ATop, Arr[Sc.FTo], A);
  end;

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

  procedure Shadowed(Id: TLayerId; Y0, Y1: Single; Proc: TDrawProc);
  begin
    TargetBand(ATop, H);
    if RowsHit(Y0, Y1 + 30) then
    begin
      if FRaster then
      begin
        if (FLayer.Width <> W) or (FLayer.Height <> LH) then FLayer.SetSize(W, LH);
        FLayerTop := LTop;
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
    if Sc.TransparentBack then Dest.FillTransparent else Dest.Fill(BGRA(150, 170, 180));
  Mark(lySky);

  if Sc.LayerOn[lyStars] then DrawStars(Dest);
  Mark(lyStars);
  if Sc.LayerOn[lyClouds] then DrawClouds(Dest);
  Mark(lyClouds);
  if Sc.LayerOn[lyFarPeaks] then Pair(Sc.FR0, Sc.FR0Pos, Sc.FSvgR0);
  Mark(lyFarPeaks);
  if Sc.LayerOn[lyMist] then DrawMist(Dest, 0);
  Mark(lyMist);
  if Sc.LayerOn[lyMidPeaks] then Pair(Sc.FR1, Sc.FR1Pos, Sc.FSvgR1);
  Mark(lyMidPeaks);
  if Sc.LayerOn[lyMist] then DrawMist(Dest, 1);
  Mark(lyMist);
  if Sc.LayerOn[lyPeaks] then Pair(Sc.FR2, Sc.FR2Pos, Sc.FSvgR2);
  Mark(lyPeaks);
  if Sc.LayerOn[lyTempleLights] then
  begin
    Lights(Sc.FTempleLit, Sc.FTempleLitPos, Sc.FSvgTempleLit);
    DrawTempleLights(Dest);
  end;
  Mark(lyTempleLights);
  if Sc.LayerOn[lyRiver] then
  begin
    Pair(Sc.FRiver, Sc.FRiverPos, Sc.FSvgRiver);
    DrawWaves(Dest);
  end;
  Mark(lyRiver);
  if Sc.LayerOn[lyMist] then DrawMist(Dest, 2);
  Mark(lyMist);
  if Sc.LayerOn[lyReflections] then DrawReflections(Dest);
  Mark(lyReflections);
  if Sc.LayerOn[lyWaterfall] then DrawWaterfall(Dest);
  Mark(lyWaterfall);
  if Sc.LayerOn[lyBoats] then Shadowed(lyBoats, RiverTop - 40, RiverBot + 10, @DrawBoats);
  Mark(lyBoats);
  if Sc.LayerOn[lyForeground] then Pair(Sc.FNear, Sc.FNearPos, Sc.FSvgNear);
  Mark(lyForeground);
  if Sc.LayerOn[lyVillageLights] then Lights(Sc.FVillageLit, Sc.FVillageLitPos, Sc.FSvgVillageLit);
  Mark(lyVillageLights);
  if Sc.LayerOn[lyLanterns] then Shadowed(lyLanterns, GroundY - 110, GroundY + 10, @DrawLanterns);
  Mark(lyLanterns);
  TargetBand(ATop, H);
  if Sc.LayerOn[lySmoke] then DrawSmoke(Dest);
  Mark(lySmoke);
  if Sc.LayerOn[lyBirds] then Shadowed(lyBirds, 120, 420, @DrawBirds);
  Mark(lyBirds);
  TargetBand(ATop, H);
  if Sc.LayerOn[lyWeather] then DrawWeather(Dest);
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
{ TMountainScene                                                          }
{ ====================================================================== }

constructor TMountainScene.Create;
begin
  inherited Create;
  FShowCaption := True;
  FillChar(LayerOn, SizeOf(LayerOn), 1);
  FVisL := 0;
  FVisR := DesignW;
  FScale := 1;
  AutoSeconds := 14;
  FadeSeconds := 2.2;
  FFrom := 1;
  FTo := 1;
  FBlend := 0;
  FSeason := 0;
  FPendingSeason := -1;
  FFlashT := 10;
  FFlashNext := 4;
  FCutter := TPainter.Create(Self);
  FAcc := TBGRABitmap.Create(1, 1);
  MakePalettes;
  Generate;
end;

destructor TMountainScene.Destroy;
begin
  FreeResources;
  FCutter.Free;
  FAcc.Free;
  FSnap.Free;
  FStaticSvg.Free;
  inherited Destroy;
end;

function TMountainScene.P(X, Y: Single): TPointF;
begin
  Result := FCutter.P(X, Y);
end;

function TMountainScene.S(V: Single): Single;
begin
  Result := V * FScale;
end;

{ height of range R at X (design): the tallest peak profile over the foot; the
  near bank is the waving ground line where no peak stands }
function TMountainScene.RangeY(R: Integer; X: Single): Single;
var
  I: Integer;
  F, Best: Single;
begin
  Best := 0;
  for I := 0 to High(FRanges[R].Peaks) do
    with FRanges[R].Peaks[I] do
      if Abs(X - C) < W then
      begin
        F := H * PeakF((X - C) / W);
        if F > Best then Best := F;
      end;
  if R = 3 then
    Result := Min(GroundY + 8 * Sin(X * 0.013) + 4 * Sin(X * 0.041), GroundY - Best)
  else
    Result := FRanges[R].Base - Best;
end;

procedure TMountainScene.MakePalettes;
var
  I: Integer;

  procedure Rng(var Pl: TPal; const A, B, C, D: string);
  begin
    Pl.Range[0] := Hex(A); Pl.Range[1] := Hex(B); Pl.Range[2] := Hex(C); Pl.Range[3] := Hex(D);
  end;

begin
  with FPal[0] do  // morning: pink haze, the sun rising low on the left
  begin
    SkyTop := Hex('#6C8CC8'); SkyBot := Hex('#F6C49A'); Glow := Hex('#FFD6A8'); SunC := Hex('#FFE3B0');
    Haze := Hex('#F6E2DA'); Water1 := Hex('#8FA6C8'); Water2 := Hex('#4E6A8E');
    Foliage := Hex('#5E8A5A'); Foliage2 := Hex('#7AA060'); Pine := Hex('#3E5E48'); Trunk := Hex('#5A4434');
    Wall := Hex('#EADFCF'); Roof := Hex('#4A4048'); Rock := Hex('#8A8078'); Lit := Hex('#FFD8B8');
    CloudLit := Hex('#FFE0D0'); CloudShade := Hex('#C8A0B0');
    SunX := 300; SunY := 400; SunR := 38; MistK := 1.4; Moon := False;
  end;
  Rng(FPal[0], '#CDB8C8', '#AEA2BC', '#7F8C9A', '#4C5E5A');
  with FPal[1] do  // day: jade peaks, high sun on the right
  begin
    SkyTop := Hex('#3C86D0'); SkyBot := Hex('#CFE8F2'); Glow := Hex('#FFFFFF'); SunC := Hex('#FFF4CC');
    Haze := Hex('#F2F8F8'); Water1 := Hex('#5AA0B8'); Water2 := Hex('#2C6A84');
    Foliage := Hex('#3F8A48'); Foliage2 := Hex('#68A858'); Pine := Hex('#2C5A3C'); Trunk := Hex('#5A4434');
    Wall := Hex('#F2EEE6'); Roof := Hex('#3E4448'); Rock := Hex('#8C8C84'); Lit := Hex('#FFF6DC');
    CloudLit := Hex('#FFFFFF'); CloudShade := Hex('#C4D4DC');
    SunX := 1250; SunY := 130; SunR := 30; MistK := 0.85; Moon := False;
  end;
  Rng(FPal[1], '#B4D2CC', '#88B8AC', '#5A9484', '#2F6250');
  with FPal[2] do  // night: indigo peaks under the moon
  begin
    SkyTop := Hex('#070B1C'); SkyBot := Hex('#22305A'); Glow := Hex('#3A4A7A'); SunC := Hex('#F4F0DC');
    Haze := Hex('#6A7AA6'); Water1 := Hex('#18264A'); Water2 := Hex('#08101E');
    Foliage := Hex('#1A3030'); Foliage2 := Hex('#22403A'); Pine := Hex('#122422'); Trunk := Hex('#1E1A1E');
    Wall := Hex('#5A6078'); Roof := Hex('#1A1C28'); Rock := Hex('#2A2E3E'); Lit := Hex('#8A9AC8');
    CloudLit := Hex('#3A4676'); CloudShade := Hex('#1C2244');
    SunX := 1300; SunY := 120; SunR := 26; MistK := 0.7; Moon := True;
  end;
  Rng(FPal[2], '#2C3C62', '#223156', '#1A2644', '#0F1A2A');
  for I := 0 to 2 do
  begin
    FPal[I].Shade := ModeShade[I];
    SeasonTint(FPal[I], I);
  end;
end;

procedure TMountainScene.SeasonTint(var Pl: TPal; M: Integer);
var
  I: Integer;
  K: Single;
begin
  K := ModeShade[M];
  Pl.Snow := Darken(Hex('#F2F6FA'), Max(0.5, K));
  Pl.SunHidden := False;
  case FSeason of
    0: ;  // summer: the base palettes
    1: begin  // rainy: grey, heavy mist, no sun
         if M = 2 then
         begin
           Pl.SkyTop := Hex('#0A0D15');
           Pl.SkyBot := Hex('#262A36');
         end
         else
         begin
           Pl.SkyTop := Darken(GreyMix(Pl.SkyTop, 0.75), 0.7);
           Pl.SkyBot := Darken(GreyMix(Pl.SkyBot, 0.7), 0.8);
           Pl.Glow := GreyMix(Pl.Glow, 0.6);
         end;
         Pl.SunHidden := True;
         for I := 0 to 3 do
           Pl.Range[I] := Mix(Darken(GreyMix(Pl.Range[I], 0.45), 0.92), Pl.SkyBot, 0.18 * (3 - I) / 3);
         Pl.Haze := GreyMix(Pl.Haze, 0.6);
         Pl.MistK := Pl.MistK * 1.7;
         Pl.Water1 := Darken(GreyMix(Pl.Water1, 0.5), 0.85);
         Pl.Water2 := Darken(GreyMix(Pl.Water2, 0.5), 0.82);
         Pl.Foliage := Darken(Pl.Foliage, 0.8);
         Pl.Foliage2 := Darken(Pl.Foliage2, 0.8);
         Pl.Pine := Darken(Pl.Pine, 0.85);
         Pl.Wall := Darken(Pl.Wall, 0.88);
         Pl.Lit := GreyMix(Pl.Lit, 0.6);
         Pl.CloudLit := Darken(Hex('#AEB4BD'), K);
         Pl.CloudShade := Darken(Hex('#7A818C'), K);
       end;
    2: begin  // autumn: red, orange and gold trees, warm hills, a big moon
         Pl.Foliage := Darken(Hex('#C8462A'), K);
         Pl.Foliage2 := Darken(Hex('#E8A830'), K);
         for I := 1 to 3 do
           Pl.Range[I] := Mix(Pl.Range[I], Darken(Hex('#9A7A48'), K), 0.22 + 0.06 * I);
         if M <> 2 then Pl.SkyBot := Mix(Pl.SkyBot, Hex('#F4D6A0'), 0.35)
         else
         begin
           Pl.SunR := 40;
           Pl.SunC := Hex('#FFE8B8');
           Pl.SunY := 150;
         end;
       end;
    3: begin  // winter: cold, snow on everything
         if M = 2 then
         begin
           Pl.SkyTop := Hex('#070C1C');
           Pl.SkyBot := Hex('#26324F');
           Pl.Snow := Hex('#5C6890');
         end
         else
         begin
           Pl.SkyTop := Mix(Pl.SkyTop, Hex('#93AACB'), 0.45);
           Pl.SkyBot := Mix(Pl.SkyBot, Hex('#E4ECF3'), 0.5);
           if M = 0 then Pl.Snow := Hex('#F2E4DE');
           Pl.CloudLit := Hex('#FFFFFF');
         end;
         for I := 0 to 3 do
           Pl.Range[I] := Mix(Pl.Range[I], Darken(Hex('#9AAAB8'), K), 0.35);
         Pl.Range[3] := Mix(Pl.Range[3], Pl.Snow, 0.6);
         Pl.Foliage := Pl.Snow;
         Pl.Foliage2 := Mix(Pl.Foliage2, Pl.Snow, 0.5);
         Pl.Water1 := Mix(Pl.Water1, Darken(Hex('#9DB8C8'), K), 0.45);
         Pl.Water2 := Mix(Pl.Water2, Darken(Hex('#5C7C93'), K), 0.45);
         Pl.Trunk := Darken(Hex('#4A3A30'), Max(0.5, K));
         Pl.CloudShade := Mix(Pl.CloudShade, Darken(Hex('#B4C2D0'), K), 0.5);
       end;
  end;
end;

{ Fixed seed: the ranges, the village, lanterns, stars, clouds, boats, birds. }
procedure TMountainScene.Generate;
var
  R, I, J, K, Tmp: Integer;
  X, W, H, Y: Single;

  procedure AddPeak(R: Integer; C, W, H: Single);
  begin
    SetLength(FRanges[R].Peaks, Length(FRanges[R].Peaks) + 1);
    FRanges[R].Peaks[High(FRanges[R].Peaks)].C := C;
    FRanges[R].Peaks[High(FRanges[R].Peaks)].W := W;
    FRanges[R].Peaks[High(FRanges[R].Peaks)].H := H;
  end;

begin
  RandSeed := 8848;
  FRanges[0].Base := Base0;
  FRanges[1].Base := Base1;
  FRanges[2].Base := Base2;
  FRanges[3].Base := GroundY;
  // far and middle ranges
  for R := 0 to 1 do
  begin
    X := -1150;
    while X < 2750 do
    begin
      W := RandRange(55, 110) - R * 8;
      H := RandRange(130, 300) - R * 20;
      AddPeak(R, X, W, H);
      X := X + W * RandRange(0.7, 1.25);
    end;
  end;
  // the karst pillars rising from the river: the waterfall cliff and the pagoda peak
  AddPeak(2, 420, 95, 330);
  AddPeak(2, PagodaX, 80, 322);
  X := -1150;
  while X < 2750 do
  begin
    W := RandRange(50, 92);
    H := RandRange(120, 290);
    if Abs(X - PagodaX) < 170 then H := Min(H, 190);
    if Abs(X - 420) < 180 then H := Min(H, 200);
    AddPeak(2, X, W, H);
    X := X + W * RandRange(1.0, 1.8);
  end;
  // the near bank: framing peaks left and right, low hills
  AddPeak(3, 10, 190, 430);
  AddPeak(3, 1600, 180, 400);
  AddPeak(3, 2000, 260, 420);
  AddPeak(3, -420, 260, 440);
  AddPeak(3, 700, 170, 34);
  // drawing order: low peaks first
  for R := 0 to 3 do
  begin
    SetLength(FRanges[R].Order, Length(FRanges[R].Peaks));
    for I := 0 to High(FRanges[R].Order) do FRanges[R].Order[I] := I;
    for I := 1 to High(FRanges[R].Order) do
    begin
      J := I;
      while (J > 0) and (FRanges[R].Peaks[FRanges[R].Order[J - 1]].H > FRanges[R].Peaks[FRanges[R].Order[J]].H) do
      begin
        Tmp := FRanges[R].Order[J];
        FRanges[R].Order[J] := FRanges[R].Order[J - 1];
        FRanges[R].Order[J - 1] := Tmp;
        Dec(J);
      end;
    end;
  end;
  // pagoda tiers on top of its pillar
  FPagodaBase := RangeY(2, PagodaX) + 2;
  Y := FPagodaBase - 3;
  for K := 0 to 6 do
  begin
    FTierY[K] := Y;
    FTierW[K] := 22 - K * 2;
    FTierH[K] := 12 - K * 0.6;
    Y := Y - FTierH[K] - 7.5;
  end;
  FWfTop := RangeY(2, WaterfallX) + 14;
  // village houses on the bank, their door lanterns and chimneys
  SetLength(FHouses, 4);
  X := 1000;
  for I := 0 to 3 do
  begin
    FHouses[I].X := X;
    FHouses[I].W := 58 + 10 * Ord(not Odd(I));
    FHouses[I].Base := RangeY(3, X + FHouses[I].W / 2) + 3;
    FHouses[I].Chimney := Odd(I) or (I = 0);
    X := X + FHouses[I].W + 20;
  end;
  SetLength(FLanterns, 0);
  SetLength(FChimneys, 0);
  for I := 0 to 3 do
    with FHouses[I] do
    begin
      for K := 0 to 1 do
      begin
        SetLength(FLanterns, Length(FLanterns) + 1);
        FLanterns[High(FLanterns)].X := X + W / 2 + (2 * K - 1) * 11;
        FLanterns[High(FLanterns)].Y := Base - 31;
        FLanterns[High(FLanterns)].Len := 8;
        FLanterns[High(FLanterns)].Size := 0.9;
        FLanterns[High(FLanterns)].Phase := I * 1.3 + K * 0.7;
      end;
      if Chimney then
      begin
        SetLength(FChimneys, Length(FChimneys) + 1);
        FChimneys[High(FChimneys)] := PointF(X + W - 16.5, Base - 58);
      end;
    end;
  SetLength(FLanterns, Length(FLanterns) + 1);
  FLanterns[High(FLanterns)].X := PavilionX;
  FLanterns[High(FLanterns)].Y := RangeY(3, PavilionX) - 50;
  FLanterns[High(FLanterns)].Len := 12;
  FLanterns[High(FLanterns)].Size := 1.2;
  FLanterns[High(FLanterns)].Phase := 4;
  // stars, clouds
  SetLength(FStars, 220);
  for I := 0 to High(FStars) do
    with FStars[I] do
    begin
      X := RandRange(-800, 2400);
      Y := RandRange(8, 420) * Power(Random, 0.3);
      R := RandRange(0.6, 1.7);
      Phase := RandRange(0, 6);
    end;
  SetLength(FClouds, 6);
  for I := 0 to High(FClouds) do
    AddCloud(I, RandRange(-200, 1800), RandRange(60, 300), RandRange(160, 300), RandRange(36, 62),
      IfThen(Odd(I), -1, 1) * RandRange(5, 12));
  // boats
  SetLength(FBoats, 3);
  FBoats[0].X := 260; FBoats[0].Y := 712; FBoats[0].Speed := 12; FBoats[0].Size := 1.35; FBoats[0].Kind := 0;
  FBoats[1].X := 980; FBoats[1].Y := 760; FBoats[1].Speed := -9; FBoats[1].Size := 1.6; FBoats[1].Kind := 1;
  FBoats[2].X := 1450; FBoats[2].Y := 690; FBoats[2].Speed := -11; FBoats[2].Size := 1.1; FBoats[2].Kind := 0;
  // cranes and the geese
  SetLength(FBirds, 5);
  for I := 0 to High(FBirds) do
    with FBirds[I] do
    begin
      X := RandRange(0, 1600);
      Y := RandRange(170, 330);
      VX := RandRange(26, 40);
      Size := RandRange(22, 30);
      Phase := RandRange(0, 6);
    end;
  FGooseX := 300;
  FGooseY := 200;
end;

procedure TMountainScene.FreeResources;
var
  M, I: Integer;
begin
  for M := 0 to 2 do
  begin
    FreeAndNil(FSky[M]);
    FreeAndNil(FR0[M]);
    FreeAndNil(FR1[M]);
    FreeAndNil(FR2[M]);
    FreeAndNil(FRiver[M]);
    FreeAndNil(FNear[M]);
    for I := 0 to High(FClouds) do
      FreeAndNil(FClouds[I].Sprite[M]);
  end;
  FreeAndNil(FTempleLit);
  FreeAndNil(FVillageLit);
  FreeAndNil(FCaption);
end;

procedure TMountainScene.Resize(AWidth, AHeight: Integer);
var
  T0: Double;
begin
  T0 := HiResMs;
  FreeAndNil(FSnap);
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
  FCutter.FRowB := MaxInt;
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

procedure TMountainScene.RenderStatic;
var
  M, I, K, Mk, N: Integer;
  Cut: TPainter;
  L, A: TBGRABitmap;
  Pl: TPal;
  X, Y, R: Single;
  Q: TPointF;
  C, SkyAtSun: TBGRAPixel;
  Pts: array of TPointF;

  procedure Begin_;
  begin
    A.FillTransparent;
    Cut.FLayerTop := 0;
    Cut.TargetBand(0, FHeight);
    if FStaticSvg <> nil then Mk := FStaticSvg.Mark else Mk := 0;
  end;

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

    { sky: wavy paper bands, the sun / moon with paper rings (overcast when rainy) }
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
        Y := 40 + K * 75 + 10 * Sin(X * 0.004 * (1 + K * 0.3) + K * 1.7) + 5 * Sin(X * 0.011 + K);
        Pts[I] := P(X, Y);
      end;
      Pts[N] := P(FVisR + 40, DesignH + 40);
      Pts[N + 1] := P(FVisL - 40, DesignH + 40);
      C := Mix(Pl.SkyTop, Pl.SkyBot, (K + 1) / 7);
      Cut.DPoly(L, Pts, C);
      Stack(0.3);
    end;
    SkyAtSun := Mix(Pl.SkyTop, Pl.SkyBot, EnsureRange((Pl.SunY - 40) / 525 + 0.1, 0, 1));
    Q := P(Pl.SunX, Pl.SunY);
    if Pl.SunHidden then
    begin
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
      Cut.Glow(A, Pl.SunX, Pl.SunY, Pl.SunR * 7, WithAlpha(Pl.Glow, IfThen(M = 2, 45, 80)));
    end;
    FSky[M] := TBGRABitmap(A.Duplicate);
    FSky[M].LoadFromBitmapIfNeeded;
    FSvgSky[M] := TakeSvg(Mk);

    { the three ranges and the bank, each its own sheet }
    Begin_;
    Sheet;
    Cut.CutRange(L, 0, Pl);
    Stack(0.3);
    Grain(A);
    FR0[M] := Crop(Base0 - 320, Base1 + 10, FR0Pos);
    FSvgR0[M] := TakeSvg(Mk);

    Begin_;
    Sheet;
    Cut.CutRange(L, 1, Pl);
    Stack(0.4);
    Grain(A);
    FR1[M] := Crop(Base1 - 300, Base2 + 10, FR1Pos);
    FSvgR1[M] := TakeSvg(Mk);

    Begin_;
    Sheet;
    Cut.CutRange(L, 2, Pl);
    Cut.CutPagoda(L, Pl);
    Stack(0.6);
    Grain(A);
    FR2[M] := Crop(Base2 - 480, Base2 + 14, FR2Pos);
    FSvgR2[M] := TakeSvg(Mk);

    Begin_;
    Cut.Box(A, FVisL - 20, RiverTop - 2, FVisR + 20, RiverBot + 6, Pl.Water1);
    Grain(A);
    FRiver[M] := Crop(RiverTop - 4, RiverBot + 8, FRiverPos);
    FSvgRiver[M] := TakeSvg(Mk);

    Begin_;
    Sheet;
    Cut.CutForeground(L, Pl);
    Stack(0.85);
    Grain(A);
    FNear[M] := Crop(220, DesignH + 2, FNearPos);
    FSvgNear[M] := TakeSvg(Mk);
  end;

  { pagoda windows at night }
  Begin_;
  for K := 0 to 6 do
  begin
    Y := FTierY[K];
    Cut.Glow(A, PagodaX, Y - FTierH[K] * 0.5, 9, WithAlpha(Hex('#FFB060'), 200));
    Cut.Box(A, PagodaX - 2.5, Y - FTierH[K] * 0.8, PagodaX + 2.5, Y - FTierH[K] * 0.2, Hex('#FFE0A0'));
    Cut.Box(A, PagodaX - FTierW[K] * 0.36, Y - FTierH[K] * 0.7, PagodaX - FTierW[K] * 0.2, Y - FTierH[K] * 0.3, Hex('#FFC878'));
    Cut.Box(A, PagodaX + FTierW[K] * 0.2, Y - FTierH[K] * 0.7, PagodaX + FTierW[K] * 0.36, Y - FTierH[K] * 0.3, Hex('#FFC878'));
  end;
  FTempleLit := Crop(FTierY[6] - 40, FPagodaBase + 6, FTempleLitPos);
  FSvgTempleLit := TakeSvg(Mk);

  { village windows, door light and the pavilion glow }
  Begin_;
  for I := 0 to High(FHouses) do
  begin
    Y := FHouses[I].Base;
    for K := 0 to 1 do
    begin
      X := FHouses[I].X + FHouses[I].W * (0.22 + 0.56 * K);
      Cut.Box(A, X - 4, Y - 27, X + 4, Y - 18, Hex('#FFD890'));
      Cut.Glow(A, X, Y - 22, 16, WithAlpha(Hex('#FFC070'), 170));
    end;
    Cut.Glow(A, FHouses[I].X + FHouses[I].W / 2, Y - 6, 22, WithAlpha(Hex('#FFB060'), 120));
  end;
  Y := RangeY(3, PavilionX);
  Cut.Glow(A, PavilionX, Y - 30, 40, WithAlpha(Hex('#FFB060'), 130));
  FVillageLit := Crop(GroundY - 160, GroundY + 30, FVillageLitPos);
  FSvgVillageLit := TakeSvg(Mk);

  CutCloudSprites;

  { caption: a red paper seal card }
  FCaption := TBGRABitmap.Create(Max(1, Round(S(460))), Max(1, Round(S(86))));
  FCaption.FillRoundRectAntialias(S(5), S(8), S(458), S(84), S(10), S(10), BGRA(0, 0, 0, 60));
  FCaption.FillRoundRectAntialias(S(1), S(1), S(450), S(76), S(10), S(10), BGRA(246, 238, 222, 240));
  FCaption.RoundRectAntialias(S(7), S(7), S(444), S(70), S(6), S(6), BGRA(178, 40, 34, 210), Max(1, S(1.4)));
  FCaption.FillRoundRectAntialias(S(400), S(14), S(434), S(48), S(4), S(4), BGRA(178, 40, 34, 230));
  FCaption.FontName := 'Segoe UI';
  FCaption.FontQuality := fqFineAntialiasing;
  FCaption.FontStyle := [fsBold];
  FCaption.FontHeight := Max(8, Round(S(26)));
  FCaption.TextOut(S(208), S(10), 'CHINESE MOUNTAINS', BGRA(48, 40, 52), taCenter);
  FCaption.FontHeight := Max(8, Round(S(22)));
  FCaption.TextOut(S(417), S(17), #$E5#$B1#$B1, BGRA(255, 240, 220), taCenter);
  FCaption.FontStyle := [];
  FCaption.FontHeight := Max(7, Round(S(14)));
  FCaption.TextOut(S(225), S(47), 'M D N A  time of day     1 2 3 4  season     I info',
    BGRA(150, 50, 40), taCenter);
  FCaption.LoadFromBitmapIfNeeded;
  FCaption.InvalidateBitmap;
  if FStaticSvg <> nil then
  begin
    Mk := FStaticSvg.Mark;
    FStaticSvg.RoundRect(S(5), S(8), S(458), S(84), S(10), S(10), BGRA(0, 0, 0, 60));
    FStaticSvg.RoundRect(S(1), S(1), S(450), S(76), S(10), S(10), BGRA(246, 238, 222, 240));
    FStaticSvg.RoundRect(S(7), S(7), S(444), S(70), S(6), S(6), BGRA(178, 40, 34, 210), Max(1, S(1.4)));
    FStaticSvg.RoundRect(S(400), S(14), S(434), S(48), S(4), S(4), BGRA(178, 40, 34, 230));
    FStaticSvg.Text(S(208), S(10), 'CHINESE MOUNTAINS', 'Segoe UI', Max(8, Round(S(26))), True,
      BGRA(48, 40, 52), True);
    FStaticSvg.Text(S(417), S(17), #$E5#$B1#$B1, 'Segoe UI', Max(8, Round(S(22))), True,
      BGRA(255, 240, 220), True);
    FStaticSvg.Text(S(225), S(47), 'M D N A  time of day     1 2 3 4  season     I info', 'Segoe UI',
      Max(7, Round(S(14))), False, BGRA(150, 50, 40), True);
    FSvgCaption := FStaticSvg.Take(Mk);
  end;
end;

procedure TMountainScene.Update(DT: Single);
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
  if FSeason = 1 then
  begin
    FFlashNext := FFlashNext - DT;
    if FFlashNext <= 0 then
    begin
      FFlashT := 0;
      FFlashNext := RandRange(8, 15);
      X := RandRange(FVisL + 120, FVisR - 120);
      Y := 20;
      SetLength(FBolt, 0);
      while Y < Base0 - 140 do
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
  for I := 0 to High(FBoats) do
    with FBoats[I] do
    begin
      X := X + Speed * DT;
      if (Speed > 0) and (X > FVisR + 140) then X := FVisL - 140;
      if (Speed < 0) and (X < FVisL - 140) then X := FVisR + 140;
    end;
  for I := 0 to High(FBirds) do
    with FBirds[I] do
    begin
      X := X + VX * DT;
      Y := Y + Sin(FTime * 0.5 + Phase) * 5 * DT;
      Phase := Phase + DT * 2.6;
      if X > FVisR + 60 then
      begin
        X := FVisL - 60 - Random(300);
        Y := RandRange(170, 330);
      end;
    end;
  FGooseX := FGooseX + 42 * DT;
  FGooseY := FGooseY - 3 * DT;
  if FGooseX > FVisR + 260 then
  begin
    FGooseX := FVisL - 80;
    FGooseY := RandRange(160, 260);
  end;
end;

procedure TMountainScene.CopyStateFrom(Src: TMountainScene);
var
  I: Integer;
begin
  FTime := Src.FTime;
  FFrom := Src.FFrom;
  FTo := Src.FTo;
  FBlend := Src.FBlend;
  FAuto := Src.FAuto;
  FAutoTimer := Src.FAutoTimer;
  AutoSeconds := Src.AutoSeconds;
  FadeSeconds := Src.FadeSeconds;
  FBoats := Copy(Src.FBoats);
  FBirds := Copy(Src.FBirds);
  FGooseX := Src.FGooseX;
  FGooseY := Src.FGooseY;
  for I := 0 to Min(High(FClouds), High(Src.FClouds)) do
    FClouds[I].OX := Src.FClouds[I].OX;
  FFlash := Src.FFlash;
  FFlashT := Src.FFlashT;
  FFlashNext := Src.FFlashNext;
  FBolt := Copy(Src.FBolt);
  FBoltOn := Src.FBoltOn;
  if Src.FSeason <> FSeason then
  begin
    FSeason := Src.FSeason;
    MakePalettes;
    if FWidth > 1 then Resize(FWidth, FHeight);
  end;
end;

function TMountainScene.SpriteCount: Integer;
begin
  Result := Length(FClouds) * 3;
end;

function TMountainScene.SpriteBytes: Int64;
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

function TMountainScene.StaticBytes: Int64;
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
    Add(FSky[M]); Add(FR0[M]); Add(FR1[M]); Add(FR2[M]); Add(FRiver[M]); Add(FNear[M]);
  end;
  Add(FTempleLit); Add(FVillageLit); Add(FCutter.FLayer); Add(FAcc);
end;

function TMountainScene.PeakCount: Integer;
var
  R: Integer;
begin
  Result := 0;
  for R := 0 to 3 do Inc(Result, Length(FRanges[R].Peaks));
end;

function TMountainScene.LanternCount: Integer;
begin
  Result := Length(FLanterns) + 14;
end;

function TMountainScene.DescribeParams: string;
var
  SL: TStringList;
  Id: TLayerId;
  M, R: Integer;

  function F(V: Single): string;
  begin
    Result := FormatFloat('0.##', V);
  end;

begin
  SL := TStringList.Create;
  try
    SL.Add('DESIGN SPACE');
    SL.Add(Format('  %d x %d design px; range feet y %d / %d / %d, river %d..%d, bank y %d',
      [DesignW, DesignH, Base0, Base1, Base2, RiverTop, RiverBot, GroundY]));
    SL.Add(Format('  pagoda x %d (base y %s), waterfall x %d (top y %s), pavilion x %d',
      [PagodaX, F(FPagodaBase), WaterfallX, F(FWfTop), PavilionX]));
    SL.Add(Format('  window %d x %d, scale %s, offset (%s, %s), visible x %s .. %s',
      [FWidth, FHeight, FormatFloat('0.0000', FScale), F(FOffX), F(FOffY), F(FVisL), F(FVisR)]));
    SL.Add('');
    SL.Add(Format('SEASON  %s  (1 summer, 2 rainy, 3 autumn, 4 winter)', [SeasonNames[FSeason]]));
    SL.Add('');
    SL.Add('TIME OF DAY');
    SL.Add(Format('  now: %s -> %s, blend %s, night amount %s, auto %s (%s s each), fade %s s',
      [ModeNames[FFrom], ModeNames[FTo], F(FBlend), F(Night), IfThen(FAuto, 'on', 'off'),
      F(AutoSeconds), F(FadeSeconds)]));
    for M := 0 to 2 do
      SL.Add(Format('  %-8s lights %s, body shade %s, mist %s, sun/moon at (%s, %s) r %s',
        [ModeNames[M], F(ModeNight[M]), F(ModeShade[M]), F(FPal[M].MistK), F(FPal[M].SunX),
        F(FPal[M].SunY), F(FPal[M].SunR)]));
    SL.Add('');
    SL.Add('LAYERS (back to front)');
    SL.Add('  Layer            Kind                  Notes');
    for Id := Low(TLayerId) to High(TLayerId) do
      SL.Add(Format('  %-16s %-21s %s', [LayerNames[Id], LayerKinds[Id], LayerNotes[Id]]));
    SL.Add('');
    SL.Add('CONTENT');
    for R := 0 to 3 do
      SL.Add(Format('  range %d: foot y %s, %d peaks', [R, F(FRanges[R].Base), Length(FRanges[R].Peaks)]));
    SL.Add(Format('  houses %d, door + pavilion lanterns %d, chimneys %d, pagoda 7 tiers / 14 eave lanterns',
      [Length(FHouses), Length(FLanterns), Length(FChimneys)]));
    SL.Add(Format('  boats %d, cranes %d, geese 9 (autumn), clouds %d, stars %d',
      [Length(FBoats), Length(FBirds), Length(FClouds), Length(FStars)]));
    SL.Add('  weather: rain 450 + 50 ripples + lightning 8-15 s; snow 420; leaves 140;');
    SL.Add('  fireflies 70; sky lanterns 16 (summer / autumn nights)');
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

end.
