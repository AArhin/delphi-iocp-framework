unit IocpHttpServerMain;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, ExtCtrls, FileCtrl, IoUtils, Vcl.Buttons,
  Iocp.Utils, Iocp.TcpSocket, Iocp.HttpServer, Iocp.HttpUtils, Iocp.Buffer, Iocp.Logger, Iocp.HttpClient;

type
  TTestIocpHttpServer = class(TIocpHttpServer)
  private
    FFastTest: Boolean;
  protected
    procedure DoOnRequest(Client: TIocpHttpConnection); override;
  public
    property FastTest: Boolean read FFastTest write FFastTest;
  end;

  TfmIocpHttpServer = class(TForm)
    Timer1: TTimer;
    Panel1: TPanel;
    Panel2: TPanel;
    btnStart: TButton;
    btnStop: TButton;
    lbConnections: TLabel;
    lbSentBytes: TLabel;
    lbRecvBytes: TLabel;
    lbHandleUsedMemory: TLabel;
    lbHandleFreeMemory: TLabel;
    lbIoUsedMemory: TLabel;
    lbIoFreeMemory: TLabel;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    Label8: TLabel;
    Label9: TLabel;
    lbRunTime: TLabel;
    Label13: TLabel;
    lbSndQueueUsedMemory: TLabel;
    lbSndQueueFreeMemory: TLabel;
    Label15: TLabel;
    Label16: TLabel;
    cbConsole: TCheckBox;
    edtPort: TLabeledEdit;
    edtSelectDir: TLabeledEdit;
    btnSelectDir: TSpeedButton;
    Label7: TLabel;
    lbPendingRequest: TLabel;
    edtTimeout: TLabeledEdit;
    edtLife: TLabeledEdit;
    chkFastTest: TCheckBox;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnStartClick(Sender: TObject);
    procedure btnStopClick(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
    procedure cbConsoleClick(Sender: TObject);
    procedure btnSelectDirClick(Sender: TObject);
    procedure chkFastTestClick(Sender: TObject);
  private
    FServer: TTestIocpHttpServer;
    FLastTick: DWORD;
    FLastSentBytes, FLastRecvBytes: Int64;

    procedure UpdateInfo;
  public
    { Public declarations }
  end;

var
  fmIocpHttpServer: TfmIocpHttpServer;

implementation

{$R *.dfm}

const
  KBYTES = Int64(1024);
  MBYTES = KBYTES * 1024;
  GBYTES = MBYTES * 1024;
  TBYTES = GBYTES * 1024;

function BytesToStr(Bytes: Int64): string;
begin
  if (Bytes = 0) then
    Result := ''
  else if (Bytes < KBYTES) then
    Result := Format('%dB', [Bytes])
  else if (Bytes < MBYTES) then
    Result := Format('%dK ', [Bytes div KBYTES]) + BytesToStr(Bytes mod KBYTES)
  else if (Bytes < GBYTES) then
    Result := Format('%dM ', [Bytes div MBYTES]) + BytesToStr(Bytes mod MBYTES)
  else if (Bytes < TBYTES) then
    Result := Format('%dG ', [Bytes div GBYTES]) + BytesToStr(Bytes mod GBYTES)
  else
    Result := Format('%dT ', [Bytes div TBYTES]) + BytesToStr(Bytes mod TBYTES);
end;

procedure TfmIocpHttpServer.btnSelectDirClick(Sender: TObject);
var
  Dir: string;
begin
  if SelectDirectory('ѡ���Ŀ¼', '', Dir) then
    edtSelectDir.Text := Dir;
end;

procedure TfmIocpHttpServer.btnStartClick(Sender: TObject);
begin
  if (edtPort.Text = '') then
  begin
    zMsgWarning(Handle, '���ò�����');
    Exit;
  end;

  FServer.Port := StrToIntDef(edtPort.Text, 80);
  FServer.Timeout := StrToIntDef(edtTimeout.Text, 0);
  FServer.ClientLife := StrToIntDef(edtLife.Text, 0);
  FServer.RootDir := edtSelectDir.Text;
  FServer.FastTest := chkFastTest.Checked;
  btnStart.Enabled := not FServer.Start;
  btnStop.Enabled := not btnStart.Enabled;

  edtPort.Enabled := btnStart.Enabled;
  edtSelectDir.Enabled := edtPort.Enabled;
  edtTimeout.Enabled := edtPort.Enabled;
  edtLife.Enabled := edtPort.Enabled;
end;

procedure TfmIocpHttpServer.btnStopClick(Sender: TObject);
begin
  btnStart.Enabled := FServer.Stop;
  btnStop.Enabled := not btnStart.Enabled;

  edtPort.Enabled := btnStart.Enabled;
  edtSelectDir.Enabled := edtPort.Enabled;
  edtTimeout.Enabled := edtPort.Enabled;
  edtLife.Enabled := edtPort.Enabled;
end;

procedure TfmIocpHttpServer.cbConsoleClick(Sender: TObject);
begin
  ShowConsoleLog(cbConsole.Checked);
end;

procedure TfmIocpHttpServer.chkFastTestClick(Sender: TObject);
begin
  FServer.FastTest := chkFastTest.Checked;
end;

procedure TfmIocpHttpServer.FormCreate(Sender: TObject);
begin
  {$ifdef WIN64}
  Caption := Caption + '(x64)';
  {$else}
  Caption := Caption + '(x86)';
  {$endif}
  FServer := TTestIocpHttpServer.Create(nil);
end;

procedure TfmIocpHttpServer.FormDestroy(Sender: TObject);
begin
  FServer.Free;
end;

procedure TfmIocpHttpServer.Timer1Timer(Sender: TObject);
begin
  UpdateInfo;
end;

procedure TfmIocpHttpServer.UpdateInfo;
  function SpeedInfo(NowBytes, LastBytes: Int64; LastTick: DWORD): string;
  var
    t: DWORD;
  begin
    Result := BytesToStr(NowBytes);

    if (NowBytes > LastBytes) then
    begin
      t := CalcTickDiff(LastTick, GetTickCount);
      if (t > 0) then
        Result := Result + ', ' + BytesToStr(Round((NowBytes-LastBytes)/t)*1000) + '/��';
    end;
  end;
begin
  if (FServer.StartTick > 0) then
    lbRunTime.Caption := TickToTimeStr(CalcTickDiff(FServer.StartTick, GetTickCount))
  else
    lbRunTime.Caption := '';
  lbConnections.Caption := IntToStr(FServer.ConnectionList.Count);
  lbSentBytes.Caption := SpeedInfo(FServer.SentBytes, FLastSentBytes, FLastTick);
  lbRecvBytes.Caption := SpeedInfo(FServer.RecvBytes, FLastRecvBytes, FLastTick);
  lbHandleUsedMemory.Caption := BytesToStr(FServer.ConnectionUsedMemory);
  lbHandleFreeMemory.Caption := BytesToStr(FServer.ConnectionFreeMemory);
  lbIoUsedMemory.Caption := BytesToStr(FServer.PerIoUsedMemory);
  lbIoFreeMemory.Caption := BytesToStr(FServer.PerIoFreeMemory);
  lbSndQueueUsedMemory.Caption := BytesToStr(FServer.IoCacheUsedMemory);
  lbSndQueueFreeMemory.Caption := BytesToStr(FServer.IoCacheFreeMemory);
  lbPendingRequest.Caption := IntToStr(FServer.PendingRequest);

  FLastSentBytes := FServer.SentBytes;
  FLastRecvBytes := FServer.RecvBytes;
  FLastTick := GetTickCount;
end;

{ TTestIocpHttpServer }

procedure TTestIocpHttpServer.DoOnRequest(Client: TIocpHttpConnection);
begin
  if FFastTest then
    Client.AnswerHTML('', 'text/plain', '', RawByteString('Hello World'))
  else
    inherited DoOnRequest(Client);
end;

end.
