object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'Leap'
  ClientHeight = 325
  ClientWidth = 527
  Color = clWindow
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  Position = poScreenCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  TextHeight = 13
  object Browser: TEdgeBrowser
    Left = 0
    Top = 0
    Width = 527
    Height = 325
    Align = alClient
    TabOrder = 0
    OnCreateWebViewCompleted = BrowserCreateWebViewCompleted
    OnDocumentTitleChanged = BrowserDocumentTitleChanged
    OnNewWindowRequested = BrowserNewWindowRequested
    OnWebResourceRequested = BrowserWebResourceRequested
    OnWindowCloseRequested = BrowserWindowCloseRequested
  end
end