program Go_VM;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.Variants, System.StrUtils, System.Math, System.Character, System.Types;

type
  TOpCode = (
    opNOP, opPUSH_INT, opPUSH_STR, opPOP, opDUP,
    opADD, opSUB, opMUL, opDIV, opMOD,
    opEQ, opNE, opLT, opLE, opGT, opGE,
    opAND, opOR, opNOT,
    opJMP, opJZ, opJNZ, opRET,
    opLOAD_LOCAL, opSTORE_LOCAL,
    opOPAQUE_TRUE, opOPAQUE_FALSE,
    opDECRYPT_CONST, opDECRYPT_STR,
    opJUNK, opCFF_DISPATCH,
    opBOGUS_JZ, opINDIRECT_JMP,
    opSUBST_ADD, opSUBST_MUL2,
    opCALL, opPRINT_ARGS);

const
  OpGoName: array[TOpCode] of string = (
    'OpNOP','OpPUSH_INT','OpPUSH_STR','OpPOP','OpDUP',
    'OpADD','OpSUB','OpMUL','OpDIV','OpMOD',
    'OpEQ','OpNE','OpLT','OpLE','OpGT','OpGE',
    'OpAND','OpOR','OpNOT',
    'OpJMP','OpJZ','OpJNZ','OpRET',
    'OpLOAD_LOCAL','OpSTORE_LOCAL',
    'OpOPAQUE_TRUE','OpOPAQUE_FALSE',
    'OpDECRYPT_CONST','OpDECRYPT_STR',
    'OpJUNK','OpCFF_DISPATCH',
    'OpBOGUS_JZ','OpINDIRECT_JMP',
    'OpSUBST_ADD','OpSUBST_MUL2',
    'OpCALL','OpPRINT_ARGS');

  ConstKey: array[0..15] of Byte =
    ($e3,$d3,$81,$6f,$af,$a9,$84,$00,$10,$cf,$0f,$fc,$45,$88,$47,$c2);
  StrKey: array[0..15] of Byte =
    ($63,$3a,$f2,$b1,$05,$8c,$21,$47,$9a,$11,$d0,$4e,$88,$2f,$66,$33);

  KnownPkgCount = 13;
  KnownPkg: array[0..KnownPkgCount - 1] of string =
    ('fmt','strings','bufio','os','math','time','sort','strconv',
     'bytes','io','syscall','runtime','unsafe');

type
  TInstruction = record
    Op: TOpCode;
    Arg: Variant;
    Comment: string;
  end;

  TBytecodeFunc = class
  public
    Name: string;
    Params: TArray<string>;
    Locals: TArray<string>;
    Code: TArray<TInstruction>;
    Constants: TArray<Variant>;
    EncryptedConstants: TDictionary<Integer, TBytes>;
    StateKey: Integer;
    constructor Create;
    destructor Destroy; override;
  end;

  TGoFunc = record
    Name: string;
    Params: string;
    Result: string;
    Body: string;
    Source: string;
  end;

  TTokenKind = (tkEOF, tkIdent, tkInt, tkString, tkOp, tkLParen, tkRParen, tkComma);
  TToken = record
    Kind: TTokenKind;
    Text: string;
    IntVal: Int64;
  end;

  TGoParser = class
  public
    class function ExtractFunctions(const Source: string): TArray<TGoFunc>;
    class function FindMatchingBrace(const S: string; AOpenPos: Integer): Integer;
    class function SplitTopLevel(const S: string; const Sep: Char): TArray<string>;
    class function SplitStatements(const Body: string): TArray<string>;
    class function ParseParamTypes(const P: string): TArray<string>;
  end;

  TCompiler = class
  private
    FObfuscate: Boolean;
    FBc: TList<TInstruction>;
    FConstants: TList<Variant>;
    FEncrypted: TDictionary<Integer, TBytes>;
    FLocals: TDictionary<string, Integer>;
    FNextLocal: Integer;
    FTokens: TArray<TToken>;
    FTokenPos: Integer;
    FFailed: Boolean;
    procedure Reset;
    procedure Emit(AOp: TOpCode; const AArg: Variant; const AComment: string = '');
    procedure PatchInstr(AIndex: Integer; AOp: TOpCode; const AArg: Variant; const AComment: string);
    function AddConst(const AVal: Variant; AEncrypt: Boolean = False): Integer;
    function AllocLocal(const AName: string): Integer;
    procedure Tokenize(const S: string);
    function Peek: TToken;
    function Take: TToken;
    function CompileExpr(const E: string): Boolean;
    function ParseExpr: Boolean;
    function ParseOr: Boolean;
    function ParseAnd: Boolean;
    function ParseCmp: Boolean;
    function ParseAdd: Boolean;
    function ParseMul: Boolean;
    function ParseUnary: Boolean;
    function ParsePrimary: Boolean;
    function CompileStmt(const S: string): Boolean;
    function CompileBlock(const B: string): Boolean;
    function CompileIf(const S: string): Boolean;
    function CompileFor(const S: string): Boolean;
    procedure ApplyObfuscation;
  public
    constructor Create(AObfuscate: Boolean);
    destructor Destroy; override;
    function CompileFunction(const AFunc: TGoFunc): TBytecodeFunc;
  end;

  TEmitter = class
  public
    class function EmitProgram(
      VmFuncs: TDictionary<string, TBytecodeFunc>;
      NativeFuncs: TDictionary<string, TGoFunc>): string;
  end;

constructor TBytecodeFunc.Create;
begin
  inherited Create;
  EncryptedConstants := TDictionary<Integer, TBytes>.Create;
  StateKey := 0;
end;

destructor TBytecodeFunc.Destroy;
begin
  EncryptedConstants.Free;
  inherited;
end;

constructor TCompiler.Create(AObfuscate: Boolean);
begin
  inherited Create;
  FObfuscate := AObfuscate;
  FBc := TList<TInstruction>.Create;
  FConstants := TList<Variant>.Create;
  FEncrypted := TDictionary<Integer, TBytes>.Create;
  FLocals := TDictionary<string, Integer>.Create;
end;

destructor TCompiler.Destroy;
begin
  FBc.Free;
  FConstants.Free;
  FEncrypted.Free;
  FLocals.Free;
  inherited;
end;

procedure TCompiler.Reset;
begin
  FBc.Clear;
  FConstants.Clear;
  FEncrypted.Clear;
  FLocals.Clear;
  FNextLocal := 0;
  FFailed := False;
end;

procedure TCompiler.Emit(AOp: TOpCode; const AArg: Variant; const AComment: string);
var
  I: TInstruction;
begin
  I.Op := AOp; I.Arg := AArg; I.Comment := AComment;
  FBc.Add(I);
end;

procedure TCompiler.PatchInstr(AIndex: Integer; AOp: TOpCode;
  const AArg: Variant; const AComment: string);
var
  I: TInstruction;
begin
  I.Op := AOp; I.Arg := AArg; I.Comment := AComment;
  FBc[AIndex] := I;
end;

function TCompiler.AddConst(const AVal: Variant; AEncrypt: Boolean): Integer;
var
  Raw, Enc: TBytes;
  S: string;
  N: Int64;
  I: Integer;
begin
  Result := FConstants.Count;
  FConstants.Add(AVal);
  if AEncrypt then
  begin
    if VarIsStr(AVal) then
    begin
      S := VarToStr(AVal);
      Raw := TEncoding.UTF8.GetBytes(S);
    end
    else
    begin
      N := AVal;
      SetLength(Raw, 8);
      Move(N, Raw[0], 8);
    end;
    SetLength(Enc, Length(Raw));
    for I := 0 to High(Raw) do
      Enc[I] := Raw[I] xor ConstKey[I mod 16];
    FEncrypted.Add(Result, Enc);
  end;
end;

function TCompiler.AllocLocal(const AName: string): Integer;
begin
  if not FLocals.TryGetValue(AName, Result) then
  begin
    Result := FNextLocal;
    FLocals.Add(AName, Result);
    Inc(FNextLocal);
  end;
end;

procedure TCompiler.Tokenize(const S: string);
var
  I, N: Integer;
  C: Char;
  Buf: string;
  Toks: TList<TToken>;
  Tok: TToken;

  procedure AddTok(K: TTokenKind; const T: string; IV: Int64 = 0);
  begin
    Tok.Kind := K; Tok.Text := T; Tok.IntVal := IV;
    Toks.Add(Tok);
  end;

  function IsIS(C: Char): Boolean;
  begin Result := CharInSet(C, ['a'..'z','A'..'Z','_']); end;

  function IsIC(C: Char): Boolean;
  begin Result := CharInSet(C, ['a'..'z','A'..'Z','0'..'9','_']); end;

  function IsD(C: Char): Boolean;
  begin Result := CharInSet(C, ['0'..'9']); end;

begin
  Toks := TList<TToken>.Create;
  try
    I := 1; N := Length(S);
    while I <= N do
    begin
      C := S[I];
      if C.IsWhiteSpace then begin Inc(I); Continue; end;

      if IsIS(C) then
      begin
        Buf := '';
        while (I <= N) and IsIC(S[I]) do begin Buf := Buf + S[I]; Inc(I); end;
        AddTok(tkIdent, Buf); Continue;
      end;

      if IsD(C) then
      begin
        Buf := '';
        while (I <= N) and IsD(S[I]) do begin Buf := Buf + S[I]; Inc(I); end;
        AddTok(tkInt, Buf, StrToInt64Def(Buf, 0)); Continue;
      end;

      if C = '"' then
      begin
        Buf := ''; Inc(I);
        while (I <= N) and (S[I] <> '"') do
        begin
          if (S[I] = '\') and (I < N) then
          begin
            Inc(I);
            case S[I] of
              'n': Buf := Buf + #10;
              't': Buf := Buf + #9;
              '"': Buf := Buf + '"';
              '\': Buf := Buf + '\';
            else Buf := Buf + S[I];
            end;
          end
          else
            Buf := Buf + S[I];
          Inc(I);
        end;
        Inc(I);
        AddTok(tkString, Buf); Continue;
      end;

      if C = '`' then
      begin
        Buf := ''; Inc(I);
        while (I <= N) and (S[I] <> '`') do begin Buf := Buf + S[I]; Inc(I); end;
        Inc(I);
        AddTok(tkString, Buf); Continue;
      end;

      if C = '(' then begin AddTok(tkLParen, '('); Inc(I); Continue; end;
      if C = ')' then begin AddTok(tkRParen, ')'); Inc(I); Continue; end;
      if C = ',' then begin AddTok(tkComma,  ','); Inc(I); Continue; end;

      if (I < N) and (Copy(S, I, 2) = '==') then begin AddTok(tkOp,'=='); Inc(I,2); Continue; end;
      if (I < N) and (Copy(S, I, 2) = '!=') then begin AddTok(tkOp,'!='); Inc(I,2); Continue; end;
      if (I < N) and (Copy(S, I, 2) = '<=') then begin AddTok(tkOp,'<='); Inc(I,2); Continue; end;
      if (I < N) and (Copy(S, I, 2) = '>=') then begin AddTok(tkOp,'>='); Inc(I,2); Continue; end;
      if (I < N) and (Copy(S, I, 2) = '&&') then begin AddTok(tkOp,'&&'); Inc(I,2); Continue; end;
      if (I < N) and (Copy(S, I, 2) = '||') then begin AddTok(tkOp,'||'); Inc(I,2); Continue; end;
      if (I < N) and (Copy(S, I, 2) = ':=') then begin AddTok(tkOp,':='); Inc(I,2); Continue; end;

      if CharInSet(C, ['+','-','*','/','%','<','>','!','=','.']) then
      begin
        AddTok(tkOp, C); Inc(I); Continue;
      end;

      Inc(I);
    end;
    AddTok(tkEOF, '');
    FTokens := Toks.ToArray;
  finally
    Toks.Free;
  end;
  FTokenPos := 0;
end;

function TCompiler.Peek: TToken;
begin
  if (FTokenPos >= 0) and (FTokenPos < Length(FTokens)) then
    Result := FTokens[FTokenPos]
  else
  begin
    Result.Kind := tkEOF; Result.Text := ''; Result.IntVal := 0;
  end;
end;

function TCompiler.Take: TToken;
begin
  Result := Peek;
  if FTokenPos < Length(FTokens) then Inc(FTokenPos);
end;

function TCompiler.CompileExpr(const E: string): Boolean;
begin
  Tokenize(E);
  FTokenPos := 0;
  Result := ParseExpr;
end;

function TCompiler.ParseExpr: Boolean;
begin
  Result := ParseOr;
end;

function TCompiler.ParseOr: Boolean;
var
  T: TToken;
begin
  if not ParseAnd then Exit(False);
  T := Peek;
  while (T.Kind = tkOp) and (T.Text = '||') do
  begin
    Take;
    if not ParseAnd then Exit(False);
    Emit(opOR, Null);
    T := Peek;
  end;
  Result := True;
end;

function TCompiler.ParseAnd: Boolean;
var
  T: TToken;
begin
  if not ParseCmp then Exit(False);
  T := Peek;
  while (T.Kind = tkOp) and (T.Text = '&&') do
  begin
    Take;
    if not ParseCmp then Exit(False);
    Emit(opAND, Null);
    T := Peek;
  end;
  Result := True;
end;

function TCompiler.ParseCmp: Boolean;
var
  T: TToken;
  Opc: TOpCode;
begin
  if not ParseAdd then Exit(False);
  T := Peek;
  while (T.Kind = tkOp) and
        ((T.Text = '==') or (T.Text = '!=') or (T.Text = '<') or
         (T.Text = '>') or (T.Text = '<=') or (T.Text = '>=')) do
  begin
    if      T.Text = '==' then Opc := opEQ
    else if T.Text = '!=' then Opc := opNE
    else if T.Text = '<'  then Opc := opLT
    else if T.Text = '>'  then Opc := opGT
    else if T.Text = '<=' then Opc := opLE
    else                       Opc := opGE;
    Take;
    if not ParseAdd then Exit(False);
    Emit(Opc, Null);
    T := Peek;
  end;
  Result := True;
end;

function TCompiler.ParseAdd: Boolean;
var
  T: TToken;
begin
  if not ParseMul then Exit(False);
  T := Peek;
  while (T.Kind = tkOp) and ((T.Text = '+') or (T.Text = '-')) do
  begin
    Take;
    if not ParseMul then Exit(False);
    if T.Text = '+' then Emit(opADD, Null) else Emit(opSUB, Null);
    T := Peek;
  end;
  Result := True;
end;

function TCompiler.ParseMul: Boolean;
var
  T: TToken;
begin
  if not ParseUnary then Exit(False);
  T := Peek;
  while (T.Kind = tkOp) and ((T.Text = '*') or (T.Text = '/') or (T.Text = '%')) do
  begin
    Take;
    if not ParseUnary then Exit(False);
    if      T.Text = '*' then Emit(opMUL, Null)
    else if T.Text = '/' then Emit(opDIV, Null)
    else                     Emit(opMOD, Null);
    T := Peek;
  end;
  Result := True;
end;

function TCompiler.ParseUnary: Boolean;
var
  T: TToken;
  ZeroIdx: Integer;
begin
  T := Peek;
  if (T.Kind = tkOp) and (T.Text = '!') then
  begin
    Take;
    if not ParseUnary then Exit(False);
    Emit(opNOT, Null);
    Exit(True);
  end;
  if (T.Kind = tkOp) and (T.Text = '-') then
  begin
    Take;
    ZeroIdx := AddConst(0, FObfuscate);
    if FObfuscate then Emit(opDECRYPT_CONST, ZeroIdx)
    else              Emit(opPUSH_INT, ZeroIdx);
    if not ParseUnary then Exit(False);
    Emit(opSUB, Null);
    Exit(True);
  end;
  Result := ParsePrimary;
end;

function TCompiler.ParsePrimary: Boolean;
var
  T, T2: TToken;
  NArgs: Integer;
  Name, FullName: string;
  IsPkg: Boolean;
  K: Integer;
begin
  T := Peek;
  if T.Kind = tkInt then
  begin
    Take;
    if FObfuscate then Emit(opDECRYPT_CONST, AddConst(T.IntVal, True))
    else              Emit(opPUSH_INT,     AddConst(T.IntVal));
    Exit(True);
  end;
  if T.Kind = tkString then
  begin
    Take;
    if FObfuscate then Emit(opDECRYPT_STR, AddConst(T.Text, True))
    else              Emit(opPUSH_STR,     AddConst(T.Text));
    Exit(True);
  end;
  if T.Kind = tkLParen then
  begin
    Take;
    if not ParseExpr then Exit(False);
    T2 := Peek;
    if T2.Kind = tkRParen then Take;
    Exit(True);
  end;
  if T.Kind = tkIdent then
  begin
    Take; Name := T.Text; FullName := Name;
    T2 := Peek;
    while (T2.Kind = tkOp) and (T2.Text = '.') do
    begin
      Take; T2 := Peek;
      if T2.Kind = tkIdent then
      begin
        if Pos('.' + T2.Text, FullName) = 0 then
        begin
          IsPkg := False;
          for K := Low(KnownPkg) to High(KnownPkg) do
            if Name = KnownPkg[K] then begin IsPkg := True; Break; end;
          if not IsPkg then FFailed := True;
        end;
        FullName := FullName + '.' + T2.Text;
        Take; T2 := Peek;
      end
      else
        Break;
    end;
    if T2.Kind = tkLParen then
    begin
      Take; NArgs := 0;
      while True do
      begin
        T2 := Peek;
        if (T2.Kind = tkRParen) or (T2.Kind = tkEOF) then Break;
        if not ParseExpr then Exit(False);
        Inc(NArgs);
        T2 := Peek;
        if T2.Kind = tkComma then begin Take; Continue; end;
        Break;
      end;
      T2 := Peek;
      if T2.Kind = tkRParen then Take;
      if (FullName = 'fmt.Println') or (FullName = 'println') or
         (FullName = 'fmt.Print')   or (FullName = 'print') then
        Emit(opPRINT_ARGS, NArgs, FullName)
      else
        Emit(opCALL, FullName + '|' + IntToStr(NArgs), FullName);
      Exit(True);
    end;
    Emit(opLOAD_LOCAL, AllocLocal(FullName), FullName);
    Exit(True);
  end;
  Emit(opPUSH_INT, AddConst(0));
  Result := True;
end;

function SplitStatementsImpl(const Body: string): TArray<string>;
var
  Res: TList<string>;
  I, Start: Integer;
  C: Char;
  InStr: Boolean;
  StrDelim: Char;
  DepthBrace, DepthParen, DepthBracket: Integer;

  procedure Flush(APos: Integer);
  var
    Part: string;
  begin
    Part := Trim(Copy(Body, Start, APos - Start));
    if Part <> '' then Res.Add(Part);
    Start := APos + 1;
  end;

begin
  Res := TList<string>.Create;
  try
    DepthBrace := 0; DepthParen := 0; DepthBracket := 0;
    Start := 1; InStr := False; StrDelim := #0;
    I := 1;
    while I <= Length(Body) do
    begin
      C := Body[I];
      if InStr then
      begin
        if C = StrDelim then InStr := False
        else if (C = '\') and (StrDelim = '"') then Inc(I);
      end
      else
      begin
        if (C = '"') or (C = '`') then begin InStr := True; StrDelim := C; end
        else if C = '{' then Inc(DepthBrace)
        else if C = '}' then Dec(DepthBrace)
        else if C = '(' then Inc(DepthParen)
        else if C = ')' then Dec(DepthParen)
        else if C = '[' then Inc(DepthBracket)
        else if C = ']' then Dec(DepthBracket)
        else if (C = #10) and (DepthBrace = 0) and (DepthParen = 0) and (DepthBracket = 0) then
          Flush(I);
      end;
      Inc(I);
    end;
    if Start <= Length(Body) then Flush(Length(Body) + 1);
    Result := Res.ToArray;
  finally
    Res.Free;
  end;
end;

function TCompiler.CompileBlock(const B: string): Boolean;
var
  Stmts: TArray<string>;
  S: string;
begin
  Stmts := SplitStatementsImpl(B);
  for S in Stmts do
    if not CompileStmt(S) then Exit(False);
  Result := True;
end;

function TCompiler.CompileStmt(const S: string): Boolean;
var
  T: string;
  I, Depth, EqPos, OpPos: Integer;
  LHS, RHS: string;
  C: Char;
begin
  T := Trim(S);
  if T = '' then Exit(True);
  if (Length(T) >= 2) and (T[1] = '/') and (T[2] = '/') then Exit(True);

  if (T = 'return') or StartsStr('return ', T) then
  begin
    RHS := Trim(Copy(T, 7, MaxInt));
    if RHS <> '' then
      if not CompileExpr(RHS) then Exit(False);
    Emit(opRET, Null);
    Exit(True);
  end;

  if (T = 'if') or StartsStr('if ', T) then Exit(CompileIf(T));
  if (T = 'for') or StartsStr('for ', T) then Exit(CompileFor(T));

  if (Length(T) >= 2) and (T[1] = '{') and (T[Length(T)] = '}') then
    Exit(CompileBlock(Copy(T, 2, Length(T) - 2)));

  Depth := 0; EqPos := 0; OpPos := 0;
  for I := 1 to Length(T) do
  begin
    C := T[I];
    if (C = '(') or (C = '{') or (C = '[') then Inc(Depth)
    else if (C = ')') or (C = '}') or (C = ']') then Dec(Depth)
    else if Depth = 0 then
    begin
      if (C = ':') and (I < Length(T)) and (T[I+1] = '=') then
      begin EqPos := I; OpPos := I + 1; Break; end;
      if (C = '=') and (I > 1) and (T[I-1] <> ':') and (T[I-1] <> '!') and
         (T[I-1] <> '<') and (T[I-1] <> '>') and (T[I-1] <> '=') then
      begin EqPos := I; OpPos := I; Break; end;
    end;
  end;

  if EqPos > 0 then
  begin
    LHS := Trim(Copy(T, 1, EqPos - 1));
    RHS := Trim(Copy(T, OpPos + 1, MaxInt));
    if (Length(LHS) > 0) and CharInSet(LHS[1], ['a'..'z','A'..'Z','_']) and
       (Pos(' ', LHS) = 0) and (Pos(',', LHS) = 0) then
    begin
      if not CompileExpr(RHS) then Exit(False);
      Emit(opSTORE_LOCAL, AllocLocal(LHS), LHS);
      Exit(True);
    end;
    if Pos(',', LHS) > 0 then FFailed := True;
  end;

  if not CompileExpr(T) then Exit(False);
  if not (StartsStr('fmt.Println', T) or StartsStr('fmt.Print', T) or
          StartsStr('println', T) or StartsStr('print', T)) then
    Emit(opPOP, Null);
  Result := True;
end;

function TCompiler.CompileIf(const S: string): Boolean;
var
  I, Depth, BrStart, BrEnd, ElsePos, JzIdx, JmpIdx: Integer;
  Cond, ConsBody, ElseTxt, ElseBody: string;
  C: Char;
begin
  I := 3;
  while (I <= Length(S)) and (S[I] = ' ') do Inc(I);
  BrStart := I; Depth := 0;
  while I <= Length(S) do
  begin
    C := S[I];
    if C = '{' then begin if Depth = 0 then Break; Inc(Depth); end
    else if C = '}' then Dec(Depth);
    Inc(I);
  end;
  if I > Length(S) then Exit(False);

  Cond := Trim(Copy(S, BrStart, I - BrStart));
  if not CompileExpr(Cond) then Exit(False);

  JzIdx := FBc.Count;
  Emit(opJZ, 0, 'if-else');

  BrEnd := TGoParser.FindMatchingBrace(S, I);
  if BrEnd < 0 then Exit(False);
  ConsBody := Copy(S, I + 1, BrEnd - I - 1);
  if not CompileBlock(ConsBody) then Exit(False);

  JmpIdx := FBc.Count;
  Emit(opJMP, 0, 'if-end');

  ElsePos := BrEnd + 1;
  while (ElsePos <= Length(S)) and (S[ElsePos] = ' ') do Inc(ElsePos);

  if (ElsePos + 4 <= Length(S)) and (Copy(S, ElsePos, 4) = 'else') then
  begin
    Inc(ElsePos, 4);
    while (ElsePos <= Length(S)) and (S[ElsePos] = ' ') do Inc(ElsePos);
    PatchInstr(JzIdx, opJZ, FBc.Count, 'if-else');

    if (ElsePos + 3 <= Length(S)) and (Copy(S, ElsePos, 3) = 'if ') then
    begin
      ElseTxt := Trim(Copy(S, ElsePos, MaxInt));
      if not CompileIf(ElseTxt) then Exit(False);
    end
    else if (ElsePos <= Length(S)) and (S[ElsePos] = '{') then
    begin
      BrEnd := TGoParser.FindMatchingBrace(S, ElsePos);
      if BrEnd < 0 then Exit(False);
      ElseBody := Copy(S, ElsePos + 1, BrEnd - ElsePos - 1);
      if not CompileBlock(ElseBody) then Exit(False);
    end;
  end
  else
    PatchInstr(JzIdx, opJZ, FBc.Count, 'if-else');

  PatchInstr(JmpIdx, opJMP, FBc.Count, 'if-end');
  Result := True;
end;

function TCompiler.CompileFor(const S: string): Boolean;
var
  I, Depth, BrStart, BrEnd, LoopStart, JzExit, P1, P2: Integer;
  C: Char;
  Header, Init, Cond, Post, Name: string;
  Idx, IdxC: Integer;
begin
  I := 3;
  while (I <= Length(S)) and (S[I] = ' ') do Inc(I);
  BrStart := I; Depth := 0;
  while I <= Length(S) do
  begin
    C := S[I];
    if C = '{' then begin if Depth = 0 then Break; Inc(Depth); end
    else if C = '}' then Dec(Depth);
    Inc(I);
  end;
  if I > Length(S) then Exit(False);

  Header := Trim(Copy(S, BrStart, I - BrStart));
  Init := ''; Cond := ''; Post := '';
  if Header <> '' then
  begin
    P1 := Pos(';', Header);
    if P1 > 0 then
    begin
      Init := Trim(Copy(Header, 1, P1 - 1));
      P2 := 0;
      for I := P1 + 1 to Length(Header) do
        if Header[I] = ';' then begin P2 := I; Break; end;
      if P2 > 0 then
      begin
        Cond := Trim(Copy(Header, P1 + 1, P2 - P1 - 1));
        Post := Trim(Copy(Header, P2 + 1, MaxInt));
      end
      else
        Cond := Trim(Copy(Header, P1 + 1, MaxInt));
    end
    else
      Cond := Header;
  end;

  if Init <> '' then
    if not CompileStmt(Init) then Exit(False);

  LoopStart := FBc.Count;
  if Cond = '' then
    Emit(opPUSH_INT, AddConst(1))
  else
    if not CompileExpr(Cond) then Exit(False);

  JzExit := FBc.Count;
  Emit(opJZ, 0, 'for-exit');

  BrEnd := TGoParser.FindMatchingBrace(S, I);
  if BrEnd < 0 then Exit(False);
  if not CompileBlock(Copy(S, I + 1, BrEnd - I - 1)) then Exit(False);

  if Post <> '' then
  begin
    if (Length(Post) > 2) and
       ((Copy(Post, Length(Post) - 1, 2) = '++') or
        (Copy(Post, Length(Post) - 1, 2) = '--')) then
    begin
      Name := Trim(Copy(Post, 1, Length(Post) - 2));
      Idx := AllocLocal(Name);
      Emit(opLOAD_LOCAL, Idx, Name);
      IdxC := AddConst(1, FObfuscate);
      if FObfuscate then Emit(opDECRYPT_CONST, IdxC)
      else              Emit(opPUSH_INT,     IdxC);
      if Copy(Post, Length(Post) - 1, 2) = '++' then Emit(opADD, Null)
      else                                            Emit(opSUB, Null);
      Emit(opSTORE_LOCAL, Idx, Name);
    end
    else
      if not CompileStmt(Post) then Exit(False);
  end;

  Emit(opJMP, LoopStart, 'for-back');
  PatchInstr(JzExit, opJZ, FBc.Count, 'for-exit');
  Result := True;
end;

procedure TCompiler.ApplyObfuscation;
var
  I, N: Integer;
  Instr, Existing: TInstruction;
  UsesStr: Boolean;
begin
  if FBc.Count = 0 then Exit;

  Instr.Op := opCFF_DISPATCH; Instr.Arg := Null; Instr.Comment := 'cff';
  FBc.Insert(0, Instr);

  for I := 0 to FBc.Count - 1 do
  begin
    Existing := FBc[I];
    if Existing.Op in [opJMP, opJZ, opJNZ, opBOGUS_JZ] then
      if not VarIsNull(Existing.Arg) and not VarIsEmpty(Existing.Arg) then
      try
        Existing.Arg := Integer(Existing.Arg) + 1;
        FBc[I] := Existing;
      except
      end;
  end;

  UsesStr := False;
  for I := 0 to FBc.Count - 1 do
    if FBc[I].Op in [opPUSH_STR, opDECRYPT_STR] then
    begin
      UsesStr := True;
      Break;
    end;

  if not UsesStr then
    for I := 0 to FBc.Count - 1 do
      if (FBc[I].Op = opADD) and (Random(100) < 30) then
      begin
        Existing := FBc[I];
        Existing.Op := opSUBST_ADD;
        Existing.Comment := 'subst-add';
        FBc[I] := Existing;
      end;

  N := 10 + Random(30);
  for I := 1 to N do
  begin
    Instr.Op := opOPAQUE_TRUE; Instr.Arg := Null; Instr.Comment := 'fake';
    FBc.Add(Instr);
    Instr.Op := opPOP; Instr.Arg := Null; Instr.Comment := 'fake-pop';
    FBc.Add(Instr);
  end;

end;

function HasUnsupportedPattern(const Body: string): Boolean;
var
  I, J, N, K, P: Integer;
  Word, L: string;
  D: Char;
  IsPkg: Boolean;
  Lines: TStringDynArray;            
begin
  Result := False;
  N := Length(Body);
  I := 1;
  while I <= N do
  begin
    if (Body[I] = '"') or (Body[I] = '`') then
    begin
      D := Body[I]; Inc(I);
      while (I <= N) and (Body[I] <> D) do
      begin
        if (Body[I] = '\') and (D = '"') then Inc(I);
        Inc(I);
      end;
      Inc(I);
      Continue;
    end;
    if CharInSet(Body[I], ['a'..'z','A'..'Z','_']) then
    begin
      J := I;
      while (J <= N) and CharInSet(Body[J], ['a'..'z','A'..'Z','0'..'9','_']) do Inc(J);
      Word := Copy(Body, I, J - I);
      if (J <= N) and (Body[J] = '.') and (J + 1 <= N) and
         CharInSet(Body[J+1], ['A'..'Z']) then
      begin
        IsPkg := False;
        for K := Low(KnownPkg) to High(KnownPkg) do
          if Word = KnownPkg[K] then begin IsPkg := True; Break; end;
        if not IsPkg then begin Result := True; Exit; end;
      end;
      I := J;
    end
    else
      Inc(I);
  end;

  Lines := SplitString(Body, #10);
  for I := 0 to High(Lines) do
  begin
    L := Lines[I];
    P := Pos(':=', L);
    if (P > 0) and (Pos(',', Copy(L, 1, P - 1)) > 0) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

function TCompiler.CompileFunction(const AFunc: TGoFunc): TBytecodeFunc;
var
  P: string;
  Parts: TArray<string>;
  I: Integer;
  BC: TBytecodeFunc;
  Pairs: TArray<TPair<string, Integer>>;
begin
  if HasUnsupportedPattern(AFunc.Body) then Exit(nil);

  Reset;
  P := Trim(AFunc.Params);
  if (Length(P) >= 2) and (P[1] = '(') and (P[Length(P)] = ')') then
    P := Copy(P, 2, Length(P) - 2);
  if P <> '' then
  begin
    Parts := TGoParser.SplitTopLevel(P, ',');
    for I := 0 to High(Parts) do
    begin
      P := Trim(Parts[I]);
      if P = '' then Continue;
      if Pos(' ', P) > 0 then P := Copy(P, 1, Pos(' ', P) - 1);
      AllocLocal(P);
    end;
  end;

  if not CompileBlock(AFunc.Body) then Exit(nil);
  if FFailed then Exit(nil);
  if (FBc.Count = 0) or (FBc[FBc.Count - 1].Op <> opRET) then
    Emit(opRET, Null);

  if FObfuscate then ApplyObfuscation;

  BC := TBytecodeFunc.Create;
  BC.Name := AFunc.Name;
  SetLength(BC.Params, FLocals.Count);
  SetLength(BC.Locals, FLocals.Count);
  Pairs := FLocals.ToArray;
  for I := 0 to High(Pairs) do
  begin
    BC.Params[I] := Pairs[I].Key;
    BC.Locals[I] := Pairs[I].Key;
  end;
  BC.Code := FBc.ToArray;
  BC.Constants := FConstants.ToArray;
  for I := 0 to FConstants.Count - 1 do
    if FEncrypted.ContainsKey(I) then
      BC.EncryptedConstants.Add(I, FEncrypted[I]);
  BC.StateKey := Random(MaxInt);
  Result := BC;
end;

class function TGoParser.FindMatchingBrace(const S: string; AOpenPos: Integer): Integer;
var
  I, Depth: Integer;
  C: Char;
  InStr: Boolean;
  StrDelim: Char;
begin
  Result := -1; Depth := 0; InStr := False; StrDelim := #0;
  I := AOpenPos;
  while I <= Length(S) do
  begin
    C := S[I];
    if InStr then
    begin
      if C = StrDelim then InStr := False
      else if (C = '\') and (StrDelim = '"') then Inc(I);
    end
    else
    begin
      if (C = '"') or (C = '`') then begin InStr := True; StrDelim := C; end
      else if C = '{' then Inc(Depth)
      else if C = '}' then
      begin
        Dec(Depth);
        if Depth = 0 then Exit(I);
      end;
    end;
    Inc(I);
  end;
end;

class function TGoParser.SplitTopLevel(const S: string; const Sep: Char): TArray<string>;
var
  Res: TList<string>;
  I, Depth, Start: Integer;
  C: Char;
  InStr: Boolean;
  StrDelim: Char;
begin
  Res := TList<string>.Create;
  try
    Depth := 0; Start := 1; InStr := False; StrDelim := #0;
    I := 1;
    while I <= Length(S) do
    begin
      C := S[I];
      if InStr then
      begin
        if C = StrDelim then InStr := False
        else if (C = '\') and (StrDelim = '"') then Inc(I);
      end
      else
      begin
        if (C = '"') or (C = '`') then begin InStr := True; StrDelim := C; end
        else if (C = '(') or (C = '{') or (C = '[') then Inc(Depth)
        else if (C = ')') or (C = '}') or (C = ']') then Dec(Depth)
        else if (C = Sep) and (Depth = 0) then
        begin
          Res.Add(Copy(S, Start, I - Start));
          Start := I + 1;
        end;
      end;
      Inc(I);
    end;
    if Start <= Length(S) then
      Res.Add(Copy(S, Start, Length(S) - Start + 1));
    Result := Res.ToArray;
  finally
    Res.Free;
  end;
end;

class function TGoParser.SplitStatements(const Body: string): TArray<string>;
begin
  Result := SplitStatementsImpl(Body);
end;

class function TGoParser.ExtractFunctions(const Source: string): TArray<TGoFunc>;
var
  Res: TList<TGoFunc>;
  I, N, P, BrOpen, BrClose, BrDepth, FuncStart: Integer;
  Params, Results, Body, Name: string;
  GF: TGoFunc;
begin
  Res := TList<TGoFunc>.Create;
  try
    I := 1; N := Length(Source);
    while I <= N do
    begin
      P := PosEx('func ', Source, I);
      if P = 0 then Break;
      if (P > 1) and CharInSet(Source[P-1], ['a'..'z','A'..'Z','0'..'9','_']) then
      begin
        I := P + 5;
        Continue;
      end;

      FuncStart := P;
      I := P + 5;
      while (I <= N) and (Source[I] = ' ') do Inc(I);
      Name := '';
      while (I <= N) and CharInSet(Source[I], ['a'..'z','A'..'Z','0'..'9','_']) do
      begin
        Name := Name + Source[I];
        Inc(I);
      end;

      while (I <= N) and (Source[I] <> '(') do Inc(I);
      if I > N then Break;
      P := I; BrDepth := 0;
      while I <= N do
      begin
        if Source[I] = '(' then Inc(BrDepth)
        else if Source[I] = ')' then
        begin
          Dec(BrDepth);
          if BrDepth = 0 then Break;
        end;
        Inc(I);
      end;
      if I > N then Break;
      Params := Copy(Source, P, I - P + 1);
      Inc(I);
      while (I <= N) and (Source[I] = ' ') do Inc(I);

      Results := '';
      while (I <= N) and (Source[I] <> '{') and (Source[I] <> #10) do
      begin
        Results := Results + Source[I];
        Inc(I);
      end;
      Results := Trim(Results);

      while (I <= N) and (Source[I] <> '{') do Inc(I);
      if I > N then Break;
      BrOpen := I;
      BrClose := FindMatchingBrace(Source, BrOpen);
      if BrClose < 0 then Break;
      Body := Copy(Source, BrOpen + 1, BrClose - BrOpen - 1);

      GF.Name := Name;
      GF.Params := Params;
      GF.Result := Results;
      GF.Body := Body;
      GF.Source := Copy(Source, FuncStart, BrClose - FuncStart + 1);
      Res.Add(GF);

      I := BrClose + 1;
    end;
    Result := Res.ToArray;
  finally
    Res.Free;
  end;
end;

class function TGoParser.ParseParamTypes(const P: string): TArray<string>;
var
  Inner: string;
  Parts: TArray<string>;
  Tokens, Tmp: TStringDynArray;       
  I, J: Integer;
  Part: string;
  Pending: TArray<string>;

  function IsTypeName(const T: string): Boolean;
  const
    Known: array[0..12] of string =
      ('int','int8','int16','int32','int64','uint','uint8','uint16',
       'uint32','uint64','uintptr','string','bool');
  var
    K: Integer;
  begin
    for K := Low(Known) to High(Known) do
      if T = Known[K] then Exit(True);
    Result := (T = 'float32') or (T = 'float64') or (T = 'byte') or
              (T = 'rune')    or (T = 'error')   or
              (T = 'interface{}') or (T = 'any');
  end;

begin
  Inner := Trim(P);
  if (Length(Inner) >= 2) and (Inner[1] = '(') and (Inner[Length(Inner)] = ')') then
    Inner := Copy(Inner, 2, Length(Inner) - 2);

  SetLength(Result, 0);
  SetLength(Pending, 0);
  if Trim(Inner) = '' then Exit;

  Parts := SplitTopLevel(Inner, ',');
  for I := 0 to High(Parts) do
  begin
    Part := Trim(Parts[I]);
    if Part = '' then Continue;

    Tokens := SplitString(Part, ' ');
    SetLength(Tmp, 0);
    for J := 0 to High(Tokens) do
      if Tokens[J] <> '' then
      begin
        SetLength(Tmp, Length(Tmp) + 1);
        Tmp[High(Tmp)] := Tokens[J];
      end;
    Tokens := Tmp;

    if Length(Tokens) = 1 then
    begin
      if IsTypeName(Tokens[0]) and (Length(Pending) > 0) then
      begin
        for J := 0 to High(Pending) do
        begin
          SetLength(Result, Length(Result) + 1);
          Result[High(Result)] := Tokens[0];
        end;
        SetLength(Pending, 0);
      end
      else if IsTypeName(Tokens[0]) then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Tokens[0];
      end
      else
      begin
        SetLength(Pending, Length(Pending) + 1);
        Pending[High(Pending)] := Tokens[0];
      end;
    end
    else
    begin
      for J := 0 to High(Pending) do
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Tokens[High(Tokens)];
      end;
      SetLength(Pending, 0);
      for J := 0 to High(Tokens) - 1 do
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Tokens[High(Tokens)];
      end;
    end;
  end;

  for J := 0 to High(Pending) do
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := 'int';
  end;
end;


function EscapeGoString(const S: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '"';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    case C of
      '\': Result := Result + '\\';
      '"': Result := Result + '\"';
      #10: Result := Result + '\n';
      #13: Result := Result + '\r';
      #9:  Result := Result + '\t';
    else
      Result := Result + C;
    end;
  end;
  Result := Result + '"';
end;

function JoinArray(const A: TArray<string>; const Sep: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(A) do
  begin
    if I > 0 then Result := Result + Sep;
    Result := Result + A[I];
  end;
end;

function SerializeConstants(Bc: TBytecodeFunc): string;
var
  I: Integer;
  V: Variant;
  Parts: TArray<string>;
begin
  SetLength(Parts, Length(Bc.Constants));
  for I := 0 to High(Bc.Constants) do
  begin
    V := Bc.Constants[I];
    if VarIsStr(V) then
      Parts[I] := EscapeGoString(VarToStr(V))
    else
      Parts[I] := 'int64(' + IntToStr(Int64(V)) + ')';
  end;
  Result := '[]interface{}{' + JoinArray(Parts, ', ') + '}';
end;

function SerializeEncrypted(Bc: TBytecodeFunc): string;
var
  K, I: Integer;
  Data: TBytes;
  Line, S: string;
  HasAny: Boolean;
begin
  HasAny := False; S := '';
  for K in Bc.EncryptedConstants.Keys do
  begin
    Data := Bc.EncryptedConstants[K];
    Line := IntToStr(K) + ': {';
    for I := 0 to High(Data) do
    begin
      if I > 0 then Line := Line + ', ';
      Line := Line + Format('0x%.2x', [Data[I]]);
    end;
    Line := Line + '}';
    if HasAny then S := S + ',' + sLineBreak + #9#9;
    S := S + Line;
    HasAny := True;
  end;
  if not HasAny then Exit('map[int][]byte{}');
  Result := 'map[int][]byte{' + sLineBreak + #9#9 + S + ',' + sLineBreak + #9 + '}';
end;

function SerializeCode(Bc: TBytecodeFunc): string;
var
  I: Integer;
  Ins: TInstruction;
  Line, ArgGo, S: string;
begin
  S := '[]Instr{' + sLineBreak;
  for I := 0 to High(Bc.Code) do
  begin
    Ins := Bc.Code[I];
    if VarIsNull(Ins.Arg) or VarIsEmpty(Ins.Arg) then
      ArgGo := 'nil'
    else if VarIsStr(Ins.Arg) then
      ArgGo := EscapeGoString(VarToStr(Ins.Arg))
    else
      ArgGo := 'int64(' + IntToStr(Int64(Ins.Arg)) + ')';
    Line := Format(#9#9'{Op: %s, Arg: %s},', [OpGoName[Ins.Op], ArgGo]);
    S := S + Line + sLineBreak;
  end;
  S := S + #9'}';
  Result := S;
end;

function SanitizeGoIdent(const N: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(N) do
  begin
    C := N[I];
    if CharInSet(C, ['a'..'z','A'..'Z','0'..'9','_']) then
      Result := Result + C
    else
      Result := Result + '_';
  end;
  if (Length(Result) > 0) and CharInSet(Result[1], ['0'..'9']) then
    Result := '_' + Result;
end;

function ConvertArg(const Expr, GoType: string): string;
begin
  if GoType = 'string' then
    Result := 'toString(' + Expr + ')'
  else if GoType = 'bool' then
    Result := 'asBool(' + Expr + ')'
  else if (GoType = 'int') or (GoType = 'int8') or (GoType = 'int16') or
          (GoType = 'int32') or (GoType = 'int64') then
    Result := GoType + '(toInt64(' + Expr + '))'
  else if (GoType = 'uint') or (GoType = 'uint8') or (GoType = 'uint16') or
          (GoType = 'uint32') or (GoType = 'uint64') or (GoType = 'uintptr') then
    Result := GoType + '(toInt64(' + Expr + '))'
  else if (GoType = 'float32') or (GoType = 'float64') then
    Result := GoType + '(toInt64(' + Expr + '))'
  else
    Result := Expr;
end;

procedure EmitBuiltinStub(Lines: TStringList; const N: string);
var
  Safe: string;
begin
  Safe := 'builtin_' + SanitizeGoIdent(N);
  Lines.Add(Format('func %s(args []interface{}) interface{} {', [Safe]));
  if N = 'len' then
  begin
    Lines.Add('	if len(args) == 0 { return int64(0) }');
    Lines.Add('	switch v := args[0].(type) {');
    Lines.Add('	case string: return int64(len(v))');
    Lines.Add('	case []byte: return int64(len(v))');
    Lines.Add('	}');
    Lines.Add('	return int64(0)');
  end
  else if N = 'cap' then
    Lines.Add('	return int64(0)')
  else if N = 'strings.TrimSpace' then
  begin
    Lines.Add('	if len(args) == 0 { return "" }');
    Lines.Add('	return strings.TrimSpace(toString(args[0]))');
  end
  else if N = 'strings.Contains' then
  begin
    Lines.Add('	if len(args) < 2 { return false }');
    Lines.Add('	return strings.Contains(toString(args[0]), toString(args[1]))');
  end
  else if N = 'strings.ToLower' then
  begin
    Lines.Add('	if len(args) == 0 { return "" }');
    Lines.Add('	return strings.ToLower(toString(args[0]))');
  end
  else if N = 'strings.ToUpper' then
  begin
    Lines.Add('	if len(args) == 0 { return "" }');
    Lines.Add('	return strings.ToUpper(toString(args[0]))');
  end
  else if N = 'bufio.NewReader' then
    Lines.Add('	return bufio.NewReader(os.Stdin)')
  else if N = 'os.Stdin' then
    Lines.Add('	return os.Stdin')
  else if N = 'messageBox' then
  begin
    Lines.Add('	if len(args) >= 3 {');
    Lines.Add('		fmt.Printf("[messageBox flags=%v] %v: %v\n", args[2], args[0], args[1])');
    Lines.Add('	} else if len(args) >= 2 {');
    Lines.Add('		fmt.Printf("[messageBox] %v: %v\n", args[0], args[1])');
    Lines.Add('	}');
    Lines.Add('	return nil');
  end
  else
  begin
    Lines.Add('	// ' + N + ': unknown external, returns nil');
    Lines.Add('	return nil');
  end;
  Lines.Add('}');
  Lines.Add('');
end;

const
  VM_RUNTIME_GO =
    '// Auto-generated VM runtime' + sLineBreak +
    'type OpCode int' + sLineBreak +
    'const (' + sLineBreak +
    '	OpNOP OpCode = iota' + sLineBreak +
    '	OpPUSH_INT' + sLineBreak + '	OpPUSH_STR' + sLineBreak +
    '	OpPOP' + sLineBreak + '	OpDUP' + sLineBreak +
    '	OpADD' + sLineBreak + '	OpSUB' + sLineBreak +
    '	OpMUL' + sLineBreak + '	OpDIV' + sLineBreak + '	OpMOD' + sLineBreak +
    '	OpEQ' + sLineBreak + '	OpNE' + sLineBreak +
    '	OpLT' + sLineBreak + '	OpLE' + sLineBreak +
    '	OpGT' + sLineBreak + '	OpGE' + sLineBreak +
    '	OpAND' + sLineBreak + '	OpOR' + sLineBreak + '	OpNOT' + sLineBreak +
    '	OpJMP' + sLineBreak + '	OpJZ' + sLineBreak +
    '	OpJNZ' + sLineBreak + '	OpRET' + sLineBreak +
    '	OpLOAD_LOCAL' + sLineBreak + '	OpSTORE_LOCAL' + sLineBreak +
    '	OpOPAQUE_TRUE' + sLineBreak + '	OpOPAQUE_FALSE' + sLineBreak +
    '	OpDECRYPT_CONST' + sLineBreak + '	OpDECRYPT_STR' + sLineBreak +
    '	OpJUNK' + sLineBreak + '	OpCFF_DISPATCH' + sLineBreak +
    '	OpBOGUS_JZ' + sLineBreak + '	OpINDIRECT_JMP' + sLineBreak +
    '	OpSUBST_ADD' + sLineBreak + '	OpSUBST_MUL2' + sLineBreak +
    '	OpCALL' + sLineBreak + '	OpPRINT_ARGS' + sLineBreak +
    ')' + sLineBreak +
    'type Instr struct {' + sLineBreak +
    '	Op  OpCode' + sLineBreak +
    '	Arg interface{}' + sLineBreak +
    '}' + sLineBreak +
    'type VMFunc struct {' + sLineBreak +
    '	Code      []Instr' + sLineBreak +
    '	Constants []interface{}' + sLineBreak +
    '	Encrypted map[int][]byte' + sLineBreak +
    '	NumLocals int' + sLineBreak +
    '	StateKey  int64' + sLineBreak +
    '}' + sLineBreak +
    'var callRegistry = map[int]func([]interface{}) interface{}{}' + sLineBreak +
    'func splitCallSpec(spec string) (int, int) {' + sLineBreak +
    '	id, nargs, bar := 0, 0, -1' + sLineBreak +
    '	for i := 0; i < len(spec); i++ {' + sLineBreak +
    '		if spec[i] == ''|'' { bar = i; break }' + sLineBreak +
    '	}' + sLineBreak +
    '	if bar < 0 { return 0, 0 }' + sLineBreak +
    '	for i := 0; i < bar; i++ { id = id*10 + int(spec[i]-''0'') }' + sLineBreak +
    '	for i := bar + 1; i < len(spec); i++ { nargs = nargs*10 + int(spec[i]-''0'') }' + sLineBreak +
    '	return id, nargs' + sLineBreak +
    '}' + sLineBreak +
    'func toInt64(v interface{}) int64 {' + sLineBreak +
    '	switch t := v.(type) {' + sLineBreak +
    '	case int64: return t' + sLineBreak +
    '	case int: return int64(t)' + sLineBreak +
    '	case bool: if t { return 1 }; return 0' + sLineBreak +
    '	default: return 0' + sLineBreak +
    '	}' + sLineBreak +
    '}' + sLineBreak +
    'func toString(v interface{}) string {' + sLineBreak +
    '	if v == nil { return "" }' + sLineBreak +
    '	if s, ok := v.(string); ok { return s }' + sLineBreak +
    '	return fmt.Sprint(v)' + sLineBreak +
    '}' + sLineBreak +
    'func asBool(v interface{}) bool {' + sLineBreak +
    '	switch t := v.(type) {' + sLineBreak +
    '	case bool: return t' + sLineBreak +
    '	case int64: return t != 0' + sLineBreak +
    '	case int: return t != 0' + sLineBreak +
    '	default: return v != nil' + sLineBreak +
    '	}' + sLineBreak +
    '}' + sLineBreak +
    'var constKey = []byte{0xe3,0xd3,0x81,0x6f,0xaf,0xa9,0x84,0x00,0x10,0xcf,0x0f,0xfc,0x45,0x88,0x47,0xc2}' + sLineBreak +
    'func decryptBytes(enc []byte) []byte {' + sLineBreak +
    '	out := make([]byte, len(enc))' + sLineBreak +
    '	for i, b := range enc { out[i] = b ^ constKey[i%len(constKey)] }' + sLineBreak +
    '	return out' + sLineBreak +
    '}' + sLineBreak +
    'func decryptConst(enc []byte) interface{} {' + sLineBreak +
    '	dec := decryptBytes(enc)' + sLineBreak +
    '	if len(dec) <= 8 {' + sLineBreak +
    '		var v int64' + sLineBreak +
    '		for i := 0; i < len(dec) && i < 8; i++ { v |= int64(dec[i]) << (8 * i) }' + sLineBreak +
    '		return v' + sLineBreak +
    '	}' + sLineBreak +
    '	return string(dec)' + sLineBreak +
    '}' + sLineBreak +
    'func runVM(f *VMFunc, args []interface{}) interface{} {' + sLineBreak +
    '	stack := make([]interface{}, 0, 64)' + sLineBreak +
    '	locals := make([]interface{}, f.NumLocals+8)' + sLineBreak +
    '	for i := range locals { locals[i] = int64(0) }' + sLineBreak +
    '	for i, a := range args { if i < len(locals) { locals[i] = a } }' + sLineBreak +
    '	pc := 0' + sLineBreak +
    '	steps := 0' + sLineBreak +
    '	const maxSteps = 2000000' + sLineBreak +
    '	push := func(v interface{}) { stack = append(stack, v) }' + sLineBreak +
    '	pop := func() interface{} {' + sLineBreak +
    '		if len(stack) == 0 { return nil }' + sLineBreak +
    '		v := stack[len(stack)-1]; stack = stack[:len(stack)-1]; return v' + sLineBreak +
    '	}' + sLineBreak +
    '	asInt := func(v interface{}) int64 {' + sLineBreak +
    '		switch t := v.(type) {' + sLineBreak +
    '		case int64: return t' + sLineBreak +
    '		case int: return int64(t)' + sLineBreak +
    '		case bool: if t { return 1 }; return 0' + sLineBreak +
    '		default: return 0' + sLineBreak +
    '		}' + sLineBreak +
    '	}' + sLineBreak +
    '	asBoolL := func(v interface{}) bool {' + sLineBreak +
    '		switch t := v.(type) {' + sLineBreak +
    '		case bool: return t' + sLineBreak +
    '		case int64: return t != 0' + sLineBreak +
    '		case int: return t != 0' + sLineBreak +
    '		default: return v != nil' + sLineBreak +
    '		}' + sLineBreak +
    '	}' + sLineBreak +
    '	for pc >= 0 && pc < len(f.Code) {' + sLineBreak +
    '		steps++; if steps > maxSteps { panic("VM max steps exceeded") }' + sLineBreak +
    '		ins := f.Code[pc]; pc++' + sLineBreak +
    '		switch ins.Op {' + sLineBreak +
    '		case OpPUSH_INT, OpPUSH_STR:' + sLineBreak +
    '			idx := int(asInt(ins.Arg))' + sLineBreak +
    '			if idx >= 0 && idx < len(f.Constants) { push(f.Constants[idx]) } else { push(int64(0)) }' + sLineBreak +
    '		case OpDECRYPT_CONST:' + sLineBreak +
    '			idx := int(asInt(ins.Arg))' + sLineBreak +
    '			if enc, ok := f.Encrypted[idx]; ok { push(decryptConst(enc)) } else if idx >= 0 && idx < len(f.Constants) { push(f.Constants[idx]) } else { push(int64(0)) }' + sLineBreak +
    '		case OpDECRYPT_STR:' + sLineBreak +
    '			idx := int(asInt(ins.Arg))' + sLineBreak +
    '			if enc, ok := f.Encrypted[idx]; ok { push(string(decryptBytes(enc))) } else if idx >= 0 && idx < len(f.Constants) { push(f.Constants[idx]) } else { push("") }' + sLineBreak +
    '		case OpPOP: pop()' + sLineBreak +
    '		case OpDUP: if len(stack) > 0 { push(stack[len(stack)-1]) }' + sLineBreak +
    '		case OpADD:' + sLineBreak +
    '			b, a := pop(), pop()' + sLineBreak +
    '			switch av := a.(type) { case string: push(av + fmt.Sprint(b)); default: push(asInt(a) + asInt(b)) }' + sLineBreak +
    '		case OpSUB: b, a := pop(), pop(); push(asInt(a) - asInt(b))' + sLineBreak +
    '		case OpMUL: b, a := pop(), pop(); push(asInt(a) * asInt(b))' + sLineBreak +
    '		case OpDIV: b, a := pop(), pop(); if asInt(b) == 0 { push(int64(0)) } else { push(asInt(a) / asInt(b)) }' + sLineBreak +
    '		case OpMOD: b, a := pop(), pop(); if asInt(b) == 0 { push(int64(0)) } else { push(asInt(a) % asInt(b)) }' + sLineBreak +
    '		case OpEQ: b, a := pop(), pop(); push(a == b)' + sLineBreak +
    '		case OpNE: b, a := pop(), pop(); push(a != b)' + sLineBreak +
    '		case OpLT: b, a := pop(), pop(); push(asInt(a) < asInt(b))' + sLineBreak +
    '		case OpLE: b, a := pop(), pop(); push(asInt(a) <= asInt(b))' + sLineBreak +
    '		case OpGT: b, a := pop(), pop(); push(asInt(a) > asInt(b))' + sLineBreak +
    '		case OpGE: b, a := pop(), pop(); push(asInt(a) >= asInt(b))' + sLineBreak +
    '		case OpAND: b, a := pop(), pop(); push(asBoolL(a) && asBoolL(b))' + sLineBreak +
    '		case OpOR: b, a := pop(), pop(); push(asBoolL(a) || asBoolL(b))' + sLineBreak +
    '		case OpNOT: push(!asBoolL(pop()))' + sLineBreak +
    '		case OpJMP: pc = int(asInt(ins.Arg))' + sLineBreak +
    '		case OpJZ: if !asBoolL(pop()) { pc = int(asInt(ins.Arg)) }' + sLineBreak +
    '		case OpJNZ: if asBoolL(pop()) { pc = int(asInt(ins.Arg)) }' + sLineBreak +
    '		case OpBOGUS_JZ: pop()' + sLineBreak +
    '		case OpINDIRECT_JMP: pc = int(asInt(ins.Arg))' + sLineBreak +
    '		case OpRET:' + sLineBreak +
    '			if len(stack) > 0 { return stack[len(stack)-1] }' + sLineBreak +
    '			return nil' + sLineBreak +
    '		case OpLOAD_LOCAL:' + sLineBreak +
    '			idx := int(asInt(ins.Arg))' + sLineBreak +
    '			if idx >= 0 && idx < len(locals) { push(locals[idx]) } else { push(int64(0)) }' + sLineBreak +
    '		case OpSTORE_LOCAL:' + sLineBreak +
    '			idx := int(asInt(ins.Arg)); v := pop()' + sLineBreak +
    '			if idx >= 0 && idx < len(locals) { locals[idx] = v }' + sLineBreak +
    '		case OpOPAQUE_TRUE: push(true)' + sLineBreak +
    '		case OpOPAQUE_FALSE: push(false)' + sLineBreak +
    '		case OpSUBST_ADD: b, a := pop(), pop(); push(asInt(a) - (-asInt(b)))' + sLineBreak +
    '		case OpSUBST_MUL2: x := pop(); push(asInt(x) + asInt(x))' + sLineBreak +
    '		case OpCALL:' + sLineBreak +
    '			spec, _ := ins.Arg.(string)' + sLineBreak +
    '			fid, nargs := splitCallSpec(spec)' + sLineBreak +
    '			callArgs := make([]interface{}, nargs)' + sLineBreak +
    '			for i := nargs - 1; i >= 0; i-- { callArgs[i] = pop() }' + sLineBreak +
    '			if fn, ok := callRegistry[fid]; ok { push(fn(callArgs)) } else { push(nil) }' + sLineBreak +
    '		case OpPRINT_ARGS:' + sLineBreak +
    '			n := int(asInt(ins.Arg))' + sLineBreak +
    '			vals := make([]interface{}, n)' + sLineBreak +
    '			for i := n - 1; i >= 0; i-- { vals[i] = pop() }' + sLineBreak +
    '			fmt.Println(vals...)' + sLineBreak +
    '		default:' + sLineBreak +
    '		}' + sLineBreak +
    '	}' + sLineBreak +
    '	if len(stack) > 0 { return stack[len(stack)-1] }' + sLineBreak +
    '	return nil' + sLineBreak +
    '}' + sLineBreak;


class function TEmitter.EmitProgram(
  VmFuncs: TDictionary<string, TBytecodeFunc>;
  NativeFuncs: TDictionary<string, TGoFunc>): string;
var
  Lines: TStringList;
  NameToId, CallNames: TDictionary<string, Integer>;
  Name, ArgS, NamePart, NumPart: string;
  Bc: TBytecodeFunc;
  Fid, NextId, I, J, Bar: Integer;
  Pair: TPair<string, Integer>;
  NeedStrings, NeedBufio, NeedOS: Boolean;
  GF: TGoFunc;
  ParamTypes: TArray<string>;
  ArgExprs: TArray<string>;
  IsNative: Boolean;

  function GetOrAssignId(const N: string): Integer;
  begin
    if not NameToId.TryGetValue(N, Result) then
    begin
      Result := NextId;
      NameToId.Add(N, Result);
      Inc(NextId);
    end;
  end;

begin
  Lines := TStringList.Create;
  NameToId := TDictionary<string, Integer>.Create;
  CallNames := TDictionary<string, Integer>.Create;
  try
    NextId := 0;

    for Name in VmFuncs.Keys do
      if Name <> 'main' then GetOrAssignId(Name);
    for Name in NativeFuncs.Keys do
      if Name <> 'main' then GetOrAssignId(Name);

    for Bc in VmFuncs.Values do
      for J := 0 to High(Bc.Code) do
        if Bc.Code[J].Op = opCALL then
        begin
          ArgS := VarToStr(Bc.Code[J].Arg);
          Bar := Pos('|', ArgS);
          if Bar > 0 then
          begin
            NamePart := Copy(ArgS, 1, Bar - 1);
            NumPart  := Copy(ArgS, Bar + 1, MaxInt);
            if (NamePart <> '') and not CharInSet(NamePart[1], ['0'..'9']) then
            begin
              Fid := GetOrAssignId(NamePart);
              Bc.Code[J].Arg := IntToStr(Fid) + '|' + NumPart;
              if not (VmFuncs.ContainsKey(NamePart) or NativeFuncs.ContainsKey(NamePart)) then
                CallNames.AddOrSetValue(NamePart, Fid);
            end;
          end;
        end;

    NeedStrings := False; NeedBufio := False; NeedOS := False;
    for Name in CallNames.Keys do
    begin
      if StartsStr('strings.', Name) then NeedStrings := True;
      if StartsStr('bufio.',   Name) then begin NeedBufio := True; NeedOS := True; end;
      if Name = 'os.Stdin'           then NeedOS := True;
    end;
    for GF in NativeFuncs.Values do
    begin
      if Pos('strings.', GF.Source) > 0 then NeedStrings := True;
      if Pos('bufio.',   GF.Source) > 0 then begin NeedBufio := True; NeedOS := True; end;
      if Pos('os.',      GF.Source) > 0 then NeedOS := True;
    end;

    Lines.Add('// Code generated by GoVMObfuscator (Delphi)');
    Lines.Add('package main');
    Lines.Add('');
    Lines.Add('import (');
    Lines.Add('	"fmt"');
    if NeedStrings then Lines.Add('	"strings"');
    if NeedBufio   then Lines.Add('	"bufio"');
    if NeedOS      then Lines.Add('	"os"');
    Lines.Add(')');
    Lines.Add('');
    Lines.Add(VM_RUNTIME_GO);
    Lines.Add('');

    Lines.Add('// ─── Bytecode tables ───');
    for Name in VmFuncs.Keys do
    begin
      Bc := VmFuncs[Name];
      Lines.Add(Format('var vmFunc_%s = &VMFunc{', [Name]));
      Lines.Add(Format('	Code:      %s,', [SerializeCode(Bc)]));
      Lines.Add(Format('	Constants: %s,', [SerializeConstants(Bc)]));
      Lines.Add(Format('	Encrypted: %s,', [SerializeEncrypted(Bc)]));
      Lines.Add(Format('	NumLocals: %d,', [Max(16, Length(Bc.Locals))]));
      Lines.Add(Format('	StateKey:  %d,', [Bc.StateKey]));
      Lines.Add('}');
      Lines.Add('');
    end;

    Lines.Add('// ─── VM wrapper functions ───');
    for Name in VmFuncs.Keys do
    begin
      if Name = 'main' then Continue;
      Lines.Add(Format('func %s(args ...interface{}) interface{} {', [Name]));
      Lines.Add(Format('	return runVM(vmFunc_%s, args)', [Name]));
      Lines.Add('}');
      Lines.Add('');
    end;

    if NativeFuncs.Count > 0 then
    begin
      Lines.Add('// ─── Native (non-virtualized) functions ───');
      for GF in NativeFuncs.Values do
      begin
        Lines.Add(GF.Source);
        Lines.Add('');
      end;
    end;

    if CallNames.Count > 0 then
    begin
      Lines.Add('// ─── Built-in / external call stubs ───');
      for Name in CallNames.Keys do
        EmitBuiltinStub(Lines, Name);
    end;

    Lines.Add('// ─── CALL registry ───');
    Lines.Add('func init() {');
    for Pair in NameToId do
    begin
      Name := Pair.Key;
      Fid  := Pair.Value;
      if CallNames.ContainsKey(Name) then Continue;
      IsNative := NativeFuncs.ContainsKey(Name);
      if IsNative then
      begin
        GF := NativeFuncs[Name];
        ParamTypes := TGoParser.ParseParamTypes(GF.Params);
        SetLength(ArgExprs, Length(ParamTypes));
        for I := 0 to High(ParamTypes) do
          ArgExprs[I] := ConvertArg(Format('args[%d]', [I]), ParamTypes[I]);
        Lines.Add(Format('	callRegistry[%d] = func(args []interface{}) interface{} {', [Fid]));
        Lines.Add(Format('		return %s(%s)', [Name, JoinArray(ArgExprs, ', ')]));
        Lines.Add('	}');
      end
      else
      begin
        Lines.Add(Format('	callRegistry[%d] = func(args []interface{}) interface{} {', [Fid]));
        Lines.Add(Format('		return %s(args...)', [Name]));
        Lines.Add('	}');
      end;
    end;
    for Pair in CallNames do
    begin
      Name := Pair.Key;
      Fid  := Pair.Value;
      Lines.Add(Format('	callRegistry[%d] = builtin_%s',
        [Fid, SanitizeGoIdent(Name)]));
    end;
    Lines.Add('}');
    Lines.Add('');

    Lines.Add('func main() {');
    if VmFuncs.ContainsKey('main') then
      Lines.Add('	runVM(vmFunc_main, nil)');
    Lines.Add('}');

    Result := Lines.Text;
  finally
    CallNames.Free;
    NameToId.Free;
    Lines.Free;
  end;
end;

procedure Run(const InputFile, OutputFile: string);
var
  Src: TStringList;
  Source, Code: string;
  Funcs: TArray<TGoFunc>;
  VmFuncs: TDictionary<string, TBytecodeFunc>;
  NativeFuncs: TDictionary<string, TGoFunc>;
  Comp: TCompiler;
  Bc: TBytecodeFunc;
  I: Integer;
  Out_: TStringList;
begin
  Src := TStringList.Create;
  VmFuncs := TDictionary<string, TBytecodeFunc>.Create;
  NativeFuncs := TDictionary<string, TGoFunc>.Create;
  try
    Src.LoadFromFile(InputFile);
    Source := Src.Text;
    Funcs := TGoParser.ExtractFunctions(Source);
    Writeln('  GoVMObfuscator (Delphi port)');
    Writeln('  ─────────────────────────────');
    Writeln(Format('[*] Found %d functions', [Length(Funcs)]));
    for I := 0 to High(Funcs) do
    begin
      Comp := TCompiler.Create(True);
      try
        Bc := Comp.CompileFunction(Funcs[I]);
        if Bc <> nil then
        begin
          VmFuncs.Add(Funcs[I].Name, Bc);
          Writeln(Format('    [VM ] %s (%d instrs)', [Funcs[I].Name, Length(Bc.Code)]));
        end
        else
        begin
          NativeFuncs.Add(Funcs[I].Name, Funcs[I]);
          Writeln(Format('    [nat] %s', [Funcs[I].Name]));
        end;
      finally
        Comp.Free;
      end;
    end;
    Code := TEmitter.EmitProgram(VmFuncs, NativeFuncs);
    Out_ := TStringList.Create;
    try
      Out_.Text := Code;
      Out_.SaveToFile(OutputFile);
    finally
      Out_.Free;
    end;
    Writeln;
    Writeln(Format('[+] Output: %s', [OutputFile]));
  finally
    for Bc in VmFuncs.Values do Bc.Free;
    VmFuncs.Free;
    NativeFuncs.Free;
    Src.Free;
  end;
end;

var
  InputFile, OutputFile: string;
begin
  if ParamCount < 1 then
  begin
    Writeln('Usage: Go_VM <input.go> [output.go]');
    ExitCode := 1;
    Halt(1);
  end;

  InputFile := ParamStr(1);
  if ParamCount >= 2 then
    OutputFile := ParamStr(2)
  else
    OutputFile := ChangeFileExt(InputFile, '_obfuscated.go');

  if not FileExists(InputFile) then
  begin
    Writeln('File not found: ', InputFile);
    ExitCode := 1;
    Halt(1);
  end;

  try
    Randomize;
    Run(InputFile, OutputFile);
  except
    on E: Exception do
    begin
      Writeln('[!] Error: ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
