unit Traynard.Tray.Native;

{$mode ObjFPC}{$H+}

{ Native system-tray icon implementation (replaces LCL TTrayIcon).

  Why
  ---
  LCL's win32 tray backend (lcl/interfaces/win32/win32trayicon.inc) registers
  every icon with the SAME NOTIFYICONDATA.uID (25) and WITHOUT a guidItem.
  Windows therefore treats all notification-area icons that belong to one
  executable as one group: they are laid out adjacently and are dragged as a
  single unit.

  This unit talks to Shell_NotifyIcon directly and assigns every icon a UNIQUE
  guidItem, so Windows identifies each icon independently and lets the user
  position / rearrange each of them separately.

  Notes
  -----
  * Self-contained: declares its own NOTIFYICONDATA record, imports
    Shell_NotifyIconW, and keeps all Win32 shell constants under a TRAY_ prefix
    so the unit does not depend on (nor collide with) the contents of the FPC
    Windows / ShellAPI units.
  * Uses the NOTIFYICON_VERSION_4 callback convention:
      wParam : LOWORD = x, HIWORD = y
      lParam : LOWORD = event, HIWORD = icon id (the uID we assigned)
  * The message window is a plain Win32 window (the same pattern already used
    by Traynard.Highlight), created lazily on first use.

  This is an UNVERIFIED DRAFT: it has not been compiled in this session. }

interface

uses
  Classes, SysUtils, Graphics, Menus, Windows, JwaWinUser;

type

  { NOTIFYICONDATAW-compatible record (Vista+, includes guidItem) }

  TNotifyIconDataEx = record
    cbSize: DWORD;
    hWnd: HWND;
    uID: UINT;
    uFlags: UINT;
    uCallbackMessage: UINT;
    hIcon: HICON;
    szTip: array[0..127] of WideChar;
    dwState: DWORD;
    dwStateMask: DWORD;
    szInfo: array[0..255] of WideChar;
    u: record
         case longint of
           0: (uTimeout: UINT);
           1: (uVersion: UINT);
       end;
    szInfoTitle: array[0..63] of WideChar;
    dwInfoFlags: DWORD;
    guidItem: TGUID;
    hBalloonIcon: HICON;
  end;

const
  { Shell_NotifyIcon dwMessage }
  TRAY_NIM_ADD          = $00000000;
  TRAY_NIM_MODIFY       = $00000001;
  TRAY_NIM_DELETE       = $00000002;
  TRAY_NIM_SETFOCUS     = $00000003;
  TRAY_NIM_SETVERSION   = $00000004;

  { NOTIFYICONDATA.uFlags }
  TRAY_NIF_MESSAGE      = $00000001;
  TRAY_NIF_ICON         = $00000002;
  TRAY_NIF_TIP          = $00000004;
  TRAY_NIF_STATE        = $00000008;
  TRAY_NIF_INFO         = $00000010;
  TRAY_NIF_GUID         = $00000020;
  TRAY_NIF_REALTIME     = $00000040;
  TRAY_NIF_SHOWTIP      = $00000080;

  TRAY_NOTIFYICON_VERSION_4 = 4;

  { balloon info flags }
  TRAY_NIIF_NONE        = $00000000;
  TRAY_NIIF_INFO        = $00000001;
  TRAY_NIIF_WARNING     = $00000002;
  TRAY_NIIF_ERROR       = $00000003;
  TRAY_NIIF_USER        = $00000004;
  TRAY_NIIF_NOSOUND     = $00000010;
  TRAY_NIIF_LARGE_ICON  = $00000020;

  { NOTIFYICON_VERSION_4 callback events (LOWORD(lParam)) }
  TRAY_NIN_SELECT           = WM_USER + 0;
  TRAY_NIN_KEYSELECT        = WM_USER + 1;
  TRAY_NIN_BALLOONSHOW      = WM_USER + 2;
  TRAY_NIN_BALLOONHIDE      = WM_USER + 3;
  TRAY_NIN_BALLOONTIMEOUT   = WM_USER + 4;
  TRAY_NIN_BALLOONUSERCLICK = WM_USER + 5;
  TRAY_NIN_POPUPOPEN        = WM_USER + 6;
  TRAY_NIN_POPUPCLOSE       = WM_USER + 7;

  WM_TRAY_CONTEXTMENU  = $007B;       // WM_CONTEXTMENU
  WM_TRAYNOTIFY        = WM_USER + 100;

  TRAY_WINDOW_CLASS    = 'TraynardNativeTrayWindow';
  TRAY_ICON_BASE_ID    = 1000;

{ Named distinctly (ShellNotifyIconW) so it can never clash with a similarly
  named declaration that may already live in the FPC Windows / ShellAPI unit. }
function ShellNotifyIconW(dwMessage: DWORD; lpData: Pointer): BOOL;
  stdcall; external 'shell32' name 'Shell_NotifyIconW';

{ Deterministic GUID derived from a key string (FNV-1a + mix). Deterministic so
  that Windows remembers the icon position across restarts when the same key is
  reused. }
function GuidFromString(const Key: string): TGUID;

type
  TNativeTrayIcon = class;
  TTrayNotifier = class;

  { TNativeTrayIcon }

  TNativeTrayIcon = class(TComponent)
  private
    FID: UINT;
    FGuid: TGUID;
    FGuidValid: Boolean;
    FIcon: TIcon;
    FHint: string;
    FVisible: Boolean;
    FPopUpMenu: TPopUpMenu;
    FOnClick: TNotifyEvent;
    FOnDblClick: TNotifyEvent;
    procedure SetHint(const AValue: string);
    procedure SetIcon(AValue: TIcon);
    procedure SetVisible(AValue: Boolean);
    procedure IconChanged(Sender: TObject);
    procedure FillIdentity(out Data: TNotifyIconDataEx);
    procedure SendModify(AFlags: UINT);
    procedure AddToTray;
    procedure RemoveFromTray;
  protected
    function MakeGuid: TGUID; virtual;
    function GetGuid: TGUID;
    procedure DoClick; virtual;
    procedure DoDblClick; virtual;
    procedure DoContextMenu(const X, Y: Integer); virtual;
    procedure DoEvent(AEvent: Cardinal; X, Y: Integer); virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ReAdd;
    procedure ShowBalloonHint(const ATitle, AText: string;
      ATimeout: Integer = 0; AFlags: DWORD = TRAY_NIIF_NONE);
    property ID: UINT read FID;
    property Guid: TGUID read GetGuid;
    property Icon: TIcon read FIcon write SetIcon;
    property Hint: string read FHint write SetHint;
    property Visible: Boolean read FVisible write SetVisible;
    property PopUpMenu: TPopUpMenu read FPopUpMenu write FPopUpMenu;
    property OnClick: TNotifyEvent read FOnClick write FOnClick;
    property OnDblClick: TNotifyEvent read FOnDblClick write FOnDblClick;
  end;

  { TTrayNotifier - owns the hidden message window and the icon registry }

  TTrayNotifier = class
  private
    FWindow: HWND;
    FIcons: TList;
    FNextID: UINT;
    procedure EnsureWindow;
    function GetWindow: HWND;
    function FindByID(AID: UINT): TNativeTrayIcon;
    procedure HandleNotify(AID: UINT; AEvent: Cardinal; X, Y: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    function RegisterIcon(AIcon: TNativeTrayIcon): UINT;
    procedure UnregisterIcon(AIcon: TNativeTrayIcon);
    procedure RecreateAll;
    property Window: HWND read GetWindow;
  end;

var
  TrayNotifier: TTrayNotifier = nil;

implementation

var
  GTaskbarCreated: UINT = 0;

function HIWORD16(const Value: PtrUInt): Word; inline;
begin
  Result := Word((Value shr 16) and $FFFF);
end;

function LOWORD16(const Value: PtrUInt): Word; inline;
begin
  Result := Word(Value and $FFFF);
end;

procedure SetTipString(const S: string; Dest: PWideChar; Max: Integer);
var
  W: UnicodeString;
  N: Integer;
begin
  W := UTF8Decode(S);
  N := Length(W);
  if N > Max - 1 then N := Max - 1;
  if N > 0 then Move(PWideChar(W)^, Dest^, N * SizeOf(WideChar));
  Dest[N] := #0;
end;

function GuidFromString(const Key: string): TGUID;
var
  H1, H2: QWord;
  I: Integer;
  B: array[0..15] of Byte;
begin
  H1 := QWord($CBF29CE484222325);   // FNV-1a 64 offset basis
  H2 := QWord($9E3779B97F4A7C15);   // golden-ratio seed
  for I := 1 to Length(Key) do
  begin
    H1 := (H1 xor QWord(Ord(Key[I]))) * QWord($00000100000001B3);
    H2 := (H2 + QWord(Ord(Key[I])) * QWord(Cardinal(I))) xor (H2 shr 29);
  end;
  Move(H1, B[0], SizeOf(H1));
  Move(H2, B[8], SizeOf(H2));
  B[6] := (B[6] and $0F) or $40;    // version 4
  B[8] := (B[8] and $3F) or $80;    // variant
  Move(B[0], Result, SizeOf(Result));
end;

{ message window procedure }

function TrayWndProc(Window: HWND; Msg: UINT; WParam: WPARAM;
  LParam: LPARAM): LRESULT; stdcall;
var
  Notifier: TTrayNotifier;
  ID: UINT;
  Event: Cardinal;
  X, Y: Integer;
begin
  if Msg = WM_CREATE then
  begin
    SetWindowLongPtr(Window, GWLP_USERDATA,
      PtrInt(LPCREATESTRUCT(LParam)^.lpCreateParams));
    Exit(0);
  end;

  Notifier := TTrayNotifier(PtrUInt(GetWindowLongPtr(Window, GWLP_USERDATA)));

  if (GTaskbarCreated <> 0) and (Msg = GTaskbarCreated) then
  begin
    if Assigned(Notifier) then Notifier.RecreateAll;
    Exit(0);
  end;

  if (Msg = WM_TRAYNOTIFY) and Assigned(Notifier) then
  begin
    ID := HIWORD16(PtrUInt(LParam));
    Event := LOWORD16(PtrUInt(LParam));
    X := SmallInt(LOWORD16(PtrUInt(WParam)));
    Y := SmallInt(HIWORD16(PtrUInt(WParam)));
    Notifier.HandleNotify(ID, Event, X, Y);
    Exit(0);
  end;

  Result := DefWindowProc(Window, Msg, WParam, LParam);
end;

{ TNativeTrayIcon }

constructor TNativeTrayIcon.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FIcon := TIcon.Create;
  FIcon.OnChange := @IconChanged;
  FHint := '';
  FVisible := False;
  FGuidValid := False;
  FID := TrayNotifier.RegisterIcon(Self);
end;

destructor TNativeTrayIcon.Destroy;
begin
  if FVisible then
  begin
    FVisible := False;
    RemoveFromTray;
  end;
  if TrayNotifier <> nil then TrayNotifier.UnregisterIcon(Self);
  FIcon.Free;
  inherited Destroy;
end;

function TNativeTrayIcon.MakeGuid: TGUID;
begin
  Result := GuidFromString(Format('Traynard/TrayIcon/%u/%d', [FID, Tag]));
end;

function TNativeTrayIcon.GetGuid: TGUID;
begin
  if not FGuidValid then
  begin
    FGuid := MakeGuid;
    FGuidValid := True;
  end;
  Result := FGuid;
end;

procedure TNativeTrayIcon.FillIdentity(out Data: TNotifyIconDataEx);
begin
  Data := Default(TNotifyIconDataEx);
  Data.cbSize := SizeOf(TNotifyIconDataEx);
  Data.hWnd := TrayNotifier.Window;
  Data.uID := FID;
  Data.guidItem := Guid;
  Data.uCallbackMessage := WM_TRAYNOTIFY;
end;

procedure TNativeTrayIcon.AddToTray;
var
  Data: TNotifyIconDataEx;
begin
  FillIdentity(Data);
  Data.uFlags := TRAY_NIF_MESSAGE or TRAY_NIF_ICON or TRAY_NIF_TIP or TRAY_NIF_GUID;
  Data.hIcon := FIcon.Handle;
  SetTipString(FHint, @Data.szTip[0], Length(Data.szTip));
  Data.u.uVersion := TRAY_NOTIFYICON_VERSION_4;

  if not ShellNotifyIconW(TRAY_NIM_ADD, @Data) then Exit;
  ShellNotifyIconW(TRAY_NIM_SETVERSION, @Data);
end;

procedure TNativeTrayIcon.RemoveFromTray;
var
  Data: TNotifyIconDataEx;
begin
  FillIdentity(Data);
  Data.uFlags := TRAY_NIF_GUID;
  ShellNotifyIconW(TRAY_NIM_DELETE, @Data);
end;

procedure TNativeTrayIcon.ReAdd;
begin
  if FVisible then AddToTray;
end;

procedure TNativeTrayIcon.SendModify(AFlags: UINT);
var
  Data: TNotifyIconDataEx;
begin
  if not FVisible then Exit;
  FillIdentity(Data);
  AFlags := AFlags or TRAY_NIF_GUID;
  Data.uFlags := AFlags;
  if (AFlags and TRAY_NIF_ICON) <> 0 then Data.hIcon := FIcon.Handle;
  if (AFlags and TRAY_NIF_TIP) <> 0 then
    SetTipString(FHint, @Data.szTip[0], Length(Data.szTip));
  ShellNotifyIconW(TRAY_NIM_MODIFY, @Data);
end;

procedure TNativeTrayIcon.SetHint(const AValue: string);
begin
  if FHint = AValue then Exit;
  FHint := AValue;
  SendModify(TRAY_NIF_TIP);
end;

procedure TNativeTrayIcon.SetIcon(AValue: TIcon);
begin
  FIcon.Assign(AValue);
end;

procedure TNativeTrayIcon.IconChanged(Sender: TObject);
begin
  SendModify(TRAY_NIF_ICON);
end;

procedure TNativeTrayIcon.SetVisible(AValue: Boolean);
begin
  if FVisible = AValue then Exit;
  FVisible := AValue;
  if FVisible then AddToTray else RemoveFromTray;
end;

procedure TNativeTrayIcon.ShowBalloonHint(const ATitle, AText: string;
  ATimeout: Integer; AFlags: DWORD);
var
  Data: TNotifyIconDataEx;
begin
  if not FVisible then Exit;
  FillIdentity(Data);
  Data.uFlags := TRAY_NIF_INFO or TRAY_NIF_GUID;
  Data.u.uTimeout := ATimeout;
  Data.dwInfoFlags := AFlags;
  SetTipString(AText, @Data.szInfo[0], Length(Data.szInfo));
  SetTipString(ATitle, @Data.szInfoTitle[0], Length(Data.szInfoTitle));
  ShellNotifyIconW(TRAY_NIM_MODIFY, @Data);
end;

procedure TNativeTrayIcon.DoClick;
begin
  if Assigned(FOnClick) then FOnClick(Self);
end;

procedure TNativeTrayIcon.DoDblClick;
begin
  if Assigned(FOnDblClick) then FOnDblClick(Self);
end;

procedure TNativeTrayIcon.DoContextMenu(const X, Y: Integer);
begin
  if FPopUpMenu = nil then Exit;
  // Required so that the menu is dismissed when the user clicks elsewhere.
  SetForegroundWindow(TrayNotifier.Window);
  FPopUpMenu.Popup(X, Y);
end;

procedure TNativeTrayIcon.DoEvent(AEvent: Cardinal; X, Y: Integer);
begin
  case AEvent of
    TRAY_NIN_SELECT, TRAY_NIN_KEYSELECT, WM_LBUTTONUP: DoClick;
    WM_LBUTTONDBLCLK: DoDblClick;
    WM_TRAY_CONTEXTMENU, WM_RBUTTONUP: DoContextMenu(X, Y);
  end;
end;

{ TTrayNotifier }

constructor TTrayNotifier.Create;
begin
  inherited Create;
  FWindow := 0;
  FIcons := TList.Create;
  FNextID := TRAY_ICON_BASE_ID;
end;

destructor TTrayNotifier.Destroy;
begin
  if FWindow <> 0 then DestroyWindow(FWindow);
  FreeAndNil(FIcons);
  inherited Destroy;
end;

procedure TTrayNotifier.EnsureWindow;
var
  WndClass: TWNDCLASSW;
begin
  if FWindow <> 0 then Exit;

  GTaskbarCreated := RegisterWindowMessageW('TaskbarCreated');

  WndClass := Default(TWNDCLASSW);
  WndClass.lpfnWndProc := @TrayWndProc;
  WndClass.hInstance := HInstance;
  WndClass.lpszClassName := TRAY_WINDOW_CLASS;
  { Qualify with Windows: JwaWinUser.RegisterClassW takes the struct by value. }
  Windows.RegisterClassW(@WndClass);

  FWindow := CreateWindowExW(0, TRAY_WINDOW_CLASS, '', 0, 0, 0, 0, 0,
    0, 0, HInstance, Self);
end;

function TTrayNotifier.GetWindow: HWND;
begin
  EnsureWindow;
  Result := FWindow;
end;

function TTrayNotifier.RegisterIcon(AIcon: TNativeTrayIcon): UINT;
begin
  EnsureWindow;
  Inc(FNextID);
  Result := FNextID;
  FIcons.Add(Pointer(AIcon));
end;

procedure TTrayNotifier.UnregisterIcon(AIcon: TNativeTrayIcon);
begin
  FIcons.Remove(Pointer(AIcon));
end;

function TTrayNotifier.FindByID(AID: UINT): TNativeTrayIcon;
var
  I: Integer;
  Icon: TNativeTrayIcon;
begin
  Result := nil;
  for I := 0 to FIcons.Count - 1 do
  begin
    Icon := TNativeTrayIcon(FIcons[I]);
    if Icon.ID = AID then Exit(Icon);
  end;
end;

procedure TTrayNotifier.HandleNotify(AID: UINT; AEvent: Cardinal; X, Y: Integer);
var
  Icon: TNativeTrayIcon;
begin
  Icon := FindByID(AID);
  if Assigned(Icon) then Icon.DoEvent(AEvent, X, Y);
end;

procedure TTrayNotifier.RecreateAll;
var
  I: Integer;
begin
  for I := 0 to FIcons.Count - 1 do
    TNativeTrayIcon(FIcons[I]).ReAdd;
end;

initialization

TrayNotifier := TTrayNotifier.Create;

finalization

FreeAndNil(TrayNotifier);

end.
