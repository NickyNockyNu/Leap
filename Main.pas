{
  Main.pas

    Copyright © 2022 Nicholas Smith

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
}

unit Main;

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  Winapi.ActiveX,

  System.SysUtils,
  System.Variants,
  System.Classes,
  System.Types,
  System.UITypes,
  System.IOUtils,
  System.Zip,
  System.Net.Mime,
  System.IniFiles,

  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.Edge,

  WebView2;

type
  TMainForm = class(TForm)
    {$REGION 'Components'}
    Browser: TEdgeBrowser;
    {$ENDREGION}

    {$REGION 'Form Events'}
    procedure FormCreate (Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    {$ENDREGION}

    {$REGION 'Browser events'}
    procedure BrowserCreateWebViewCompleted(Sender: TCustomEdgeBrowser; AResult: HRESULT);
    procedure BrowserWebResourceRequested  (Sender: TCustomEdgeBrowser; Args: TWebResourceRequestedEventArgs);
    procedure BrowserDocumentTitleChanged  (Sender: TCustomEdgeBrowser; const ADocumentTitle: string);
    procedure BrowserNewWindowRequested    (Sender: TCustomEdgeBrowser; Args: TNewWindowRequestedEventArgs);
    procedure BrowserWindowCloseRequested  (Sender: TObject);
    {$ENDREGION}
  private
    {$REGION 'Fields'}
    FSource:    String;
    FContainer: TZipFile;
    FConfig:    TMemIniFile;
    FTitle:     String;
    FIndex:     String;
    FStyles:    TStringList;
    FScripts:   TStringList;
    FModules:   TStringList;
    FBody:      String;
    {$ENDREGION}

    {$REGION 'Methods'}
    function GetStream(FileName: String): TStream;
    function GetString(FileName: String): String;

    function GetDefault: String;

    procedure GetParams;
    procedure LoadConfig;
    {$ENDREGION}
  end;

var
  MainForm: TMainForm;

const
  LocalHost = 'http://localhost/';

implementation

{$R *.dfm}

{$REGION 'FormEvents'}
procedure TMainForm.FormCreate(Sender: TObject);
begin
  FModules := TStringList.Create;
  FScripts := TStringList.Create;
  FStyles  := TStringList.Create;


  GetParams;

  LoadConfig;

  Browser.Navigate(LocalHost);
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  if Assigned(FContainer) then
    FreeAndNil(FContainer);

  if Assigned(FConfig) then
    FreeAndNil(FConfig);

  FStyles.Free;
  FScripts.Free;
  FModules.Free;
end;
{$ENDREGION}

{$REGION 'Browser events'}
procedure TMainForm.BrowserCreateWebViewCompleted(Sender: TCustomEdgeBrowser; AResult: HRESULT);
begin
  Sender.DefaultContextMenusEnabled := FConfig.ReadBool('Browser', 'ContextMenus', True);
  Sender.BuiltInErrorPageEnabled    := FConfig.ReadBool('Browser', 'ErrorPages',   True);
  Sender.ZoomControlEnabled         := FConfig.ReadBool('Browser', 'ZoomControl',  True);
  Sender.StatusBarEnabled           := FConfig.ReadBool('Browser', 'StatusBar',    True);

  Sender.DevToolsEnabled := FConfig.ReadBool('Developer', 'Enabled', False);
  if Sender.DevToolsEnabled and FConfig.ReadBool('Developer', 'OpenTools', False) then
    Sender.DefaultInterface.OpenDevToolsWindow;

  Sender.AddWebResourceRequestedFilter(LocalHost + '*', COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
end;

procedure TMainForm.BrowserWebResourceRequested(Sender: TCustomEdgeBrowser; Args: TWebResourceRequestedEventArgs);
var
  Request:  ICoreWebView2WebResourceRequest;
  URI:      PWideChar;
  FileName: String;
  Response: ICoreWebView2WebResourceResponse;
begin
  Args.ArgsInterface.Get_Request(Request);
  Request.Get_uri(URI);

  FileName := URI;

  if FileName.StartsWith(LocalHost, True) then
    FileName := Copy(FileName, Length(LocalHost) + 1)
  else
    Exit;

  if FileName.Contains('?') then
    FileName := Copy(FileName, 1, Pos('?', FileName) - 1);

  try
    Sender.EnvironmentInterface.CreateWebResourceResponse(TStreamAdapter.Create(GetStream(FileName), soOwned), 200, 'OK', '', Response);
  except
    Sender.EnvironmentInterface.CreateWebResourceResponse(nil, 404, 'Not Found', '', Response);
  end;

  Args.ArgsInterface.Set_Response(Response);
end;

procedure TMainForm.BrowserDocumentTitleChanged(Sender: TCustomEdgeBrowser; const ADocumentTitle: string);
begin
  Caption := ADocumentTitle;
end;

procedure TMainForm.BrowserNewWindowRequested(Sender: TCustomEdgeBrowser; Args: TNewWindowRequestedEventArgs);
var
  URI: PWideChar;
begin
  Args.ArgsInterface.Get_uri(URI);

  if String(URI).StartsWith(LocalHost, True) then
  begin
    Args.ArgsInterface.Set_Handled(1);
    Browser.Navigate(URI);
  end;
end;

procedure TMainForm.BrowserWindowCloseRequested(Sender: TObject);
begin
  Close;
end;
{$ENDREGION}

{$REGION 'Methods'}
function TMainForm.GetStream(FileName: String): TStream;
begin
  if FileName.IsEmpty then
    Result := TStringStream.Create(GetDefault)
  else if Assigned(FContainer) then
  begin
    var Header: TZipHeader;

    FContainer.Read(FileName, Result, Header);

    if Header.CompressionMethod = Word(TZipCompression.zcStored) then
    begin
      var Stream := TMemoryStream.Create;
      Stream.CopyFrom(Result, Header.UncompressedSize);

      Result.Free;
      Result := Stream;
    end;
  end
  else
  begin
    FileName := FileName.Replace('/', '\');
    FileName := FSource + FileName;

    Result := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  end;
end;

function TMainForm.GetString(FileName: String): String;
var
  StringList: TStringList;
  Stream:     TStream;
begin
  Stream := GetStream(FileName);
  if Stream = nil then
    Exit('');

  StringList := TStringList.Create;

  try
    StringList.LoadFromStream(Stream);
    Result := StringList.Text;
  finally
    StringList.Free;
  end;
end;

function TMainForm.GetDefault: String;
const
  CRLF = #13#10;
begin

  try
    if not FIndex.IsEmpty then
      Result := GetString(FIndex);
  except
    Result := '';
  end;

  if Result.IsEmpty then
  begin
    Result :=
      '<!DOCTYPE html>'#13#10 +
      '<html>' + CRLF +
        '<head>' + CRLF +
          '<title>' + FTitle + '</title>' + CRLF;

    for var Style in FStyles do
      if not Style.IsEmpty then
        Result := Result + '<link rel="stylesheet" href="' + Style + '">' + CRLF;

    for var Script in FScripts do
      if not Script.IsEmpty then
        Result := Result + '<script type="text/javascript" src="' + Script + '"></script>' + CRLF;

    for var Module in FModules do
      if not Module.IsEmpty then
        Result := Result + '<script type="module" src="' + Module + '"></script>' + CRLF;

    Result := Result +
        '</head>' + CRLF +
        '<body>' + CRLF;

    if not FBody.IsEmpty then
      try
        Result := Result + GetString(FBody);
      except
        {}
      end;

    Result := Result +
        '</body>' + CRLF +
      '</html>' + CRLF;
  end;
end;

procedure TMainForm.GetParams;
begin
  for var i := 1 to ParamCount do
    if not ParamStr(i).IsEmpty then
    begin
      if ParamStr(i).StartsWith('-') then
        // Option
      else if FSource.IsEmpty then
        FSource := ParamStr(i);
    end;

  if FSource.IsEmpty then
  begin
    ShowMessage('Usage: Leap.exe "D:\Path\to\project\"');
    Halt;
  end;

  if TDirectory.Exists(FSource) then
  begin
    if not FSource.EndsWith(TPath.DirectorySeparatorChar) then
      FSource := FSource + TPath.DirectorySeparatorChar;
  end

  else if TZipFile.IsValid(FSource) then
  begin
    FContainer := TZipFile.Create;
    FContainer.Open(FSource, zmRead);
  end

  else
  begin
    ShowMessage('Cannot open the project');
    Halt;
  end;
end;

procedure TMainForm.LoadConfig;
var
  Strings: TStringList;
begin
  if Assigned(FConfig) then
    FreeAndNil(FConfig);

  FConfig := TMemIniFile.Create('');

  Strings := TStringList.Create;
  try
    Strings.LoadFromStream(GetStream('config.ini'));
  except
    {}
  end;

  FConfig.SetStrings(Strings);

  Strings.Free;

  if FConfig.ReadBool('Content', 'Resizeable', True) then
  begin
    BorderStyle := bsSizeable;
    BorderIcons := [biSystemMenu, biMinimize, biMaximize];
  end
  else
  begin
    BorderStyle := bsSingle;
    BorderIcons := [biSystemMenu, biMinimize];
  end;

  ClientWidth  := FConfig.ReadInteger('Content', 'Width',  ClientWidth);
  ClientHeight := FConfig.ReadInteger('Content', 'Height', ClientHeight);

  FTitle  := FConfig.ReadString('Content', 'Title', Caption);
  Caption := FTitle;

  FIndex  := FConfig.ReadString('Content', 'Index',  '');
  FBody   := FConfig.ReadString('Content', 'Body',   '');

  try
    Icon.LoadFromStream(GetStream('favicon.ico'));
  except
    {}
  end;

  FConfig.ReadSection('Modules', FModules);
  FConfig.ReadSection('Scripts', FScripts);
  FConfig.ReadSection('Styles',  FStyles);
end;
{$ENDREGION}

end.
