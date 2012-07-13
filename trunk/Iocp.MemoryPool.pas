unit Iocp.MemoryPool;

{$define __ZERO_MEMORY__}

interface

uses
  Windows, Classes, SysUtils, SyncObjs, Iocp.Logger;

type
  TIocpMemoryPool = class
  private
    FRefCount: Integer;
    FHeapHandle: THandle;
    FBlockSize, FMaxFreeBlocks: Integer;
    FFreeMemoryBlockList: TList; // ����ʵ�ʲ��ԣ�ʹ��Classes.TList��Collections.TList<>Ч�ʸ���
    FUsedMemoryBlockList: TList;
    FLocker: TCriticalSection;

    function GetFreeBlocks: Integer;
    function GetFreeBlocksSize: Integer;
    function GetUsedBlocks: Integer;
    function GetUsedBlocksSize: Integer;
    procedure SetMaxFreeBlocks(MaxFreeBlocks: Integer);
  public
    constructor Create(BlockSize, MaxFreeBlocks: Integer); virtual;
    destructor Destroy; override;

    procedure Lock;
    procedure Unlock;
    function AddRef: Integer;
    function Release: Boolean;
    function GetMemory: Pointer;
    procedure FreeMemory(const P: Pointer);
    procedure Clear;

    property MaxFreeBlocks: Integer read FMaxFreeBlocks write SetMaxFreeBlocks;

    property FreeMemoryBlockList: TList read FFreeMemoryBlockList;
    property UsedMemoryBlockList: TList read FUsedMemoryBlockList;
    property BlockSize: Integer read FBlockSize;
    property FreeBlocks: Integer read GetFreeBlocks;
    property FreeBlocksSize: Integer read GetFreeBlocksSize;
    property UsedBlocks: Integer read GetUsedBlocks;
    property UsedBlocksSize: Integer read GetUsedBlocksSize;
  end;

implementation

{ TIocpMemoryPool }

constructor TIocpMemoryPool.Create(BlockSize, MaxFreeBlocks: Integer);
begin
  // ���С��64�ֽڶ��룬������ִ��Ч�����
  if (BlockSize mod 64 = 0) then
    FBlockSize := BlockSize
  else
    FBlockSize := (BlockSize div 64) * 64 + 64;
    
  FMaxFreeBlocks := MaxFreeBlocks;
  FFreeMemoryBlockList := TList.Create;
  FUsedMemoryBlockList := TList.Create;
  FLocker := TCriticalSection.Create;
  FHeapHandle := GetProcessHeap;
  FRefCount := 1;
end;

destructor TIocpMemoryPool.Destroy;
begin
  Clear;

  FFreeMemoryBlockList.Free;
  FUsedMemoryBlockList.Free;
  FLocker.Free;
  
  inherited Destroy;
end;

procedure TIocpMemoryPool.Lock;
begin
  FLocker.Enter;
end;

procedure TIocpMemoryPool.Unlock;
begin
  FLocker.Leave;
end;

function TIocpMemoryPool.AddRef: Integer;
begin
  Result := InterlockedIncrement(FRefCount);
end;

function TIocpMemoryPool.Release: Boolean;
begin
  Result := (InterlockedDecrement(FRefCount) = 0);
  if Result then Free;
end;

function TIocpMemoryPool.GetMemory: Pointer;
var
  AllocFlag: DWORD;
begin
  Lock;
  try
    Result := nil;

    // �ӿ����ڴ���б���ȡһ��
    if (FFreeMemoryBlockList.Count > 0) then
    begin
      Result := FFreeMemoryBlockList[FFreeMemoryBlockList.Count - 1];
      FFreeMemoryBlockList.Delete(FFreeMemoryBlockList.Count - 1);
    end;

    // ���û�п����ڴ�飬�����µ��ڴ��
    if (Result = nil) then
    begin
      {$ifdef __ZERO_MEMORY__}
      AllocFlag := 0;
      {$else}
      AllocFlag := $08;
      {$endif}
      Result := HeapAlloc(FHeapHandle, AllocFlag, FBlockSize);
      AddRef;
    end;

    if (Result <> nil) then
    begin
      // ��ȡ�õ��ڴ�������ʹ���ڴ���б�
      FUsedMemoryBlockList.Add(Result);
    end else
      raise Exception.CreateFmt('�����ڴ��ʧ�ܣ����С: %d', [FBlockSize]);
  finally
    Unlock;
  end;
end;

procedure TIocpMemoryPool.FreeMemory(const P: Pointer);
begin
  if (P = nil) then Exit;

  Lock;
  try
    // ����ʹ���ڴ���б����Ƴ��ڴ��
    if (FUsedMemoryBlockList.Extract(P) = nil) then Exit;

    // ����������ڴ��û�г��꣬���ڴ��ŵ������ڴ���б���
    if (FFreeMemoryBlockList.Count < FMaxFreeBlocks) then
      FFreeMemoryBlockList.Add(P)
    // �����ͷ��ڴ�
    else
    begin
      HeapFree(FHeapHandle, 0, P);
      Release;
    end;
  finally
    Unlock;
  end;
end;

procedure TIocpMemoryPool.Clear;
var
  P: Pointer;
begin
  Lock;
  try
    // ��տ����ڴ�
    while (FFreeMemoryBlockList.Count > 0) do
    begin
      P := FFreeMemoryBlockList[FFreeMemoryBlockList.Count - 1];
      if (P <> nil) then
        HeapFree(FHeapHandle, 0, P);
      FFreeMemoryBlockList.Delete(FFreeMemoryBlockList.Count - 1);
      Release;
    end;

    // �����ʹ���ڴ�
    while (FUsedMemoryBlockList.Count > 0) do
    begin
      P := FUsedMemoryBlockList[FUsedMemoryBlockList.Count - 1];
      if (P <> nil) then
        HeapFree(FHeapHandle, 0, P);
      FUsedMemoryBlockList.Delete(FUsedMemoryBlockList.Count - 1);
      Release;
    end;
  finally
    Unlock;
  end;
end;

function TIocpMemoryPool.GetFreeBlocks: Integer;
begin
  Result := FFreeMemoryBlockList.Count;
end;

function TIocpMemoryPool.GetFreeBlocksSize: Integer;
begin
  Result := FFreeMemoryBlockList.Count * FBlockSize;
end;

function TIocpMemoryPool.GetUsedBlocks: Integer;
begin
  Result := FUsedMemoryBlockList.Count;
end;

function TIocpMemoryPool.GetUsedBlocksSize: Integer;
begin
  Result := FUsedMemoryBlockList.Count * FBlockSize;
end;

procedure TIocpMemoryPool.SetMaxFreeBlocks(MaxFreeBlocks: Integer);
begin
  Lock;
  FMaxFreeBlocks := MaxFreeBlocks;
  Unlock;
end;

end.
