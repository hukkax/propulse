(*
 * Based on PT2PLAY v1.3b by Olav "8bitbubsy" S�rensen - http://16-bits.org
 * BLEP (Band-Limited Step) and filter routines by aciddose
 *
 * Delphi port by hukka, April-August 2016
 *)

unit ProTracker.Player;

interface

uses
	{$IFDEF FPC}
		{$IFDEF BASS_DYNAMIC}
		lazdynamic_bass,
		{$ELSE}
		BASS,
		{$ENDIF}
	{$ELSE}
		BASS,
	{$ENDIF}
	Generics.Collections,
	hkaFileUtils,
	ProTracker.Util,
	ProTracker.Sample,
	ProTracker.Paula,
	ProTracker.Filters;


const
	OFFSET_SONGTITLE	= 0;
	OFFSET_SAMPLEINFO	= 20;
	OFFSET_ORDERLIST	= 952;
	OFFSET_ID			= 1080;
	OFFSET_PATTERNS		= 1084;

	MAX_PATTERNS	= 100;

	MODFILESIZE_MIN =    2108;
	MODFILESIZE_MAX = 4195326;

	DATA_AUDIO		= 0;
	DATA_SAMPLE		= 1;

	AMOUNT_CHANNELS	= 4;

	PLAY_STOPPED	= 0;
	PLAY_SONG		= 1;
	PLAY_PATTERN	= 2;

	PAULA_PAL_CLK = 3546895;
	CIA_PAL_CLK   = 709379;

type
	TModuleEvent   		= procedure of Object;
	TProgressEvent 		= procedure (Progress: Cardinal) of Object;
	TProgressInitEvent 	= procedure (Max: Cardinal; const Title: String) of Object;
	TModifiedEvent 		= procedure (B: Boolean = True; Force: Boolean = False) of Object;

	TModuleFormat = (
		FORMAT_MK,     // ProTracker 1.x
		FORMAT_MK2,    // ProTracker 2.x (if tune has >64 patterns)
		FORMAT_FLT4,   // StarTrekker
		FORMAT_4CHN,   // FastTracker II (only 4 channel MODs)
		FORMAT_STK,    // The Ultimate SoundTracker (15 samples)
		FORMAT_NT,     // NoiseTracker 1.0
		FORMAT_FEST,   // NoiseTracker (special one)
		FORMAT_UNKNOWN
	);

	TNote = packed record
		Sample:			Byte;	// 8 bits
		Command:		Byte;	// 4 bits
		Parameter:		Byte;	// 8 bits
		Text:			Byte;	// index to NoteText[]
		Period:			Word;	// 12 bits (Period)
		CmdText:        String[3];

		procedure		ParseText;
		procedure		GetText;
	end;
	PNote = ^TNote;

	TSongPosition = record
		Pattern,
		Row,
		Order:	Byte;
	end;

	TOrderList = record
	private
		FItems: 	packed array [0..127] of Byte;
		function	GetItem(Index: Byte): Byte;
		procedure	SetItem(Index: Byte; const Value: Byte);
	public
		function 	GetHighestUsed: Byte;
		procedure	Insert(Index: Byte; const Value: Byte);
		procedure	Delete(Index: Byte);
		property 	Items[Index: Byte]: Byte read GetItem write SetItem; default;
	end;

	TPTChannel = class
	public
		Enabled: 		Boolean;
		Paula: 			TPaulaVoice;
		Note:			PNote;
		n_start,
		n_wavestart,
		n_loopstart:	Cardinal;
		n_index,
		n_volume,
		n_toneportdirec,
		n_vibratopos,
		n_tremolopos,
		n_pattpos,
		n_loopcount:	ShortInt;
		n_wavecontrol,
		n_glissfunk,
		n_sampleoffset,
		n_toneportspeed,
		n_vibratocmd,
		n_tremolocmd,
		n_finetune,
		n_funkoffset:	Byte;
		n_sample,
		n_period,
		n_note,
		n_wantedperiod:	SmallInt;
		n_length,
		n_replen,
		n_repend: 		Cardinal;

		procedure 	Reset;
		constructor Create(i: Byte);
		destructor  Destroy; override;
	end;

	TPTModule = class
	private
		StereoSeparation:	Byte;
		FilterHi, FilterLo:	TLossyIntegrator;
		FilterLEDC: 		TLedFilterCoeff;
		FilterLED: 			TLedFilter;
		LEDStatus: 			Boolean;
		Blep, BlepVol: 		array [0..AMOUNT_CHANNELS-1] of TBlep;

		DisableMixer: 		Boolean;
		samplesPerFrame: 	Cardinal;
		MixBuffer: 			array of SmallInt;

		procedure 	ClearRowVisitTable;

		procedure	MixSampleBlock(streamOut: Pointer; numSamples: Cardinal);
		procedure 	CalculatePans(percentage: Byte);

		procedure	UpdateFunk(var ch: TPTChannel);
		procedure	SetGlissControl(var ch: TPTChannel);
		procedure 	SetVibratoControl(var ch: TPTChannel);
		procedure 	SetFineTune(var ch: TPTChannel);
		procedure 	JumpLoop(var ch: TPTChannel);
		procedure 	SetTremoloControl(var ch: TPTChannel);
		procedure 	KarplusStrong(var ch: TPTChannel);
		procedure 	DoRetrg(var ch: TPTChannel);
		procedure 	RetrigNote(var ch: TPTChannel);
		procedure 	VolumeSlide(var ch: TPTChannel);
		procedure 	VolumeFineUp(var ch: TPTChannel);
		procedure 	VolumeFineDown(var ch: TPTChannel);
		procedure 	NoteCut(var ch: TPTChannel);
		procedure 	NoteDelay(var ch: TPTChannel);
		procedure 	PatternDelay(var ch: TPTChannel);
		procedure 	FunkIt(var ch: TPTChannel);
		procedure 	PositionJump(var ch: TPTChannel);
		procedure 	VolumeChange(var ch: TPTChannel);
		procedure 	PatternBreak(var ch: TPTChannel);
		procedure 	SetSpeed(var ch: TPTChannel);
		procedure 	Arpeggio(var ch: TPTChannel);
		procedure 	PortaUp(var ch: TPTChannel);
		procedure 	PortaDown(var ch: TPTChannel);
		procedure 	FilterOnOff(var ch: TPTChannel);
		procedure 	FinePortaUp(var ch: TPTChannel);
		procedure 	FinePortaDown(var ch: TPTChannel);
		procedure 	SetTonePorta(var ch: TPTChannel);
		procedure 	TonePortNoChange(var ch: TPTChannel);
		procedure 	TonePortamento(var ch: TPTChannel);
		procedure 	VibratoNoChange(var ch: TPTChannel);
		procedure 	Vibrato(var ch: TPTChannel);
		procedure 	TonePlusVolSlide(var ch: TPTChannel);
		procedure 	VibratoPlusVolSlide(var ch: TPTChannel);
		procedure 	Tremolo(var ch: TPTChannel);
		procedure 	SampleOffset(var ch: TPTChannel);
		procedure 	E_Commands(var ch: TPTChannel);
		procedure 	CheckMoreEffects(var ch: TPTChannel);
		procedure 	CheckEffects(var ch: TPTChannel);
		procedure 	SetPeriod(var ch: TPTChannel);
		procedure 	SetReplayerBPM(bpm: Byte);

		procedure 	SetOutputFreq(Hz: Cardinal);

	public

		RenderInfo: record
			SamplesRendered: 	Int64;
			LastRow:			Byte;
			RowsRendered:		Byte;
			OrderChanges: 		Word;
			TimesLooped,
			LoopsWanted: 		Byte;
			Canceled,
			HasBeenPlayed: 		Boolean;
			RowVisitTable: 		array [0..MAX_PATTERNS-1, 0..63] of Boolean;
		end;

		Notes: 			array [0..MAX_PATTERNS, 0..AMOUNT_CHANNELS-1, 0..63] of TNote; // pattern - track - row
		Channel:		array [0..AMOUNT_CHANNELS-1] of TPTChannel;
		Samples: 		TObjectList<TSample>; // array [0..30]  of TSample;
		OrderList:		TOrderList;
		PlayMode:		Byte;
		Warnings:		Boolean;
		ClippedSamples: Integer;
		SampleChanged:  array[0..31] of Boolean;

		Info: record
			Format:			TModuleFormat;
			ID:				packed array [0..3]  of AnsiChar;
			Title:			packed array [0..19] of AnsiChar;
			RestartPos: 	Byte;
			OrderCount,
			PatternCount,
			Tempo,
			BPM: 			Word;
			Filesize:		Cardinal;
			Filename:		String;
		end;

		ImportInfo: record
			Samples: TObjectList<TImportedSample>;
		end;

		SamplesOnly:		Boolean;

		FilterHighPass: 	Boolean; 	// 5.2Hz high-pass filter present in all Amigas
		FilterLowPass: 		Boolean; 	// 4.4kHz low-pass filter in all Amigas except A1200
		UseBlep: 			Boolean; 	// Reduces some unwanted aliasing (closer to real Amiga)
		PreventClipping: 	Boolean; 	// Clamps the audio output to prevent clipping
		NormFactor: 		Single; 	// Sound amplification factor

		Modified,
		PosJumpAssert,
		PBreakFlag: 		Boolean;

		TempoMode: 			ShortInt;	// 0 = CIA, 1 = VBlank
		PBreakPosition: 	ShortInt;
		PattDelTime,
		PattDelTime2: 		ShortInt;

		LowMask,
		Counter,
		CurrentSpeed,
		CurrentBPM:			Byte;
		soundBufferSize: 	Integer;

		PlayPos:			TSongPosition;

		OnFilter,
		OnPlayModeChange,
		OnSpeedChange
		{OnRowChange,
		OnOrderChange}:		TModuleEvent;

		OnProgressInit:		TProgressInitEvent;
		OnProgress:			TProgressEvent;
		OnModified: 		TModifiedEvent;

		PlayStarted:		TDateTime;

		RenderMode:			(RENDER_NONE, RENDER_LENGTH, RENDER_SAMPLE, RENDER_FILE);

		procedure 	RepostChanges;
		procedure 	SetModified(B: Boolean = True; Force: Boolean = False);

		procedure 	ClearAllNoteTexts;
		procedure 	GetAllNoteTexts;

		function 	LoadFromFile(const Filename: String): Boolean;
		function 	SaveToFile(const Filename: String): Boolean;

		function 	RenderPatternFloat(var FloatBuf: TFloatArray; Rows: Byte;
					Mono, Normalize, BoostHighs: Boolean): Cardinal;
		function 	RenderPattern(var Buf: TArray<SmallInt>;
					Rows: Byte; Mono, Normalize, BoostHighs: Boolean): Cardinal;
		function 	RenderToSample(DestSample: Byte; Period: Word; Rows: Byte;
					Normalize, BoostHighs: Boolean): Cardinal;
		function 	PatternToWAV(const Filename: String; Period: Word; Rows: Byte;
					Normalize, BoostHighs: Boolean): Cardinal;
		function 	RenderToWAV(const Filename: String; Loops: Byte = 1; Tail: Byte = 0): Cardinal;
		function	GetLength(Loops: Byte = 0; InSamples: Boolean = False): Cardinal;

		function 	IsPatternEmpty(i: Byte): Boolean;
		function 	CountUsedPatterns: Byte;
		procedure 	IndexSamples;

		procedure 	SetTitle(const S: AnsiString);
		procedure 	SetTempo(bpm: Word);

		procedure 	Reset;
		procedure 	InitPlay(pattern: Byte);
		procedure 	PlayPattern(pattern: Byte; row: Byte = 0);
		procedure 	Play(order: Byte = 0; row: Byte = 0);
		procedure 	Stop;
		procedure 	Pause(Pause: Boolean = True);
		procedure 	Close;

		procedure 	PlayNote(Note: PNote; Chan: Byte);
		procedure 	PlaySample(_note, _sample, _channel: Byte;
					_volume: ShortInt = -1; _start: Integer = 0; _length: Integer = 0);
		procedure 	PlayVoice(var ch: TPTChannel);

		procedure 	NextPosition;
		procedure 	IntMusic;

		procedure 	ApplyAudioSettings;

		constructor	Create(aSamplesOnly: Boolean);
		destructor	Destroy; override;
	end;


	function	AudioInit(WinHandle: Cardinal): Boolean;
	procedure	AudioClose;


var
	Module: TPTModule;
	Stream: HSTREAM;
	VUbuffer: array of SmallInt;
	VUhandled: Boolean;
	EmptyNote: TNote;
	AudioDriver: Byte;
	MSG_VUMETER,
	MSG_ROWCHANGE,
	MSG_ORDERCHANGE,
	MSG_TIMERTICK:	UInt32;


implementation

uses
	{$IFDEF WINDOWS}
	Windows,
	{$ENDIF}
	Classes, SysUtils, Math,
//	WaveIOX,
	SDL2,
	ProTracker.Editor,
	ProTracker.Format.IT,
	ProTracker.Format.P61;

var
	Mixing: Boolean;
	samplesLeft: Cardinal;
	outputFreq: Cardinal;
	MainWindow: Cardinal;


// ==========================================================================
// Orderlist
// ==========================================================================

function TOrderList.GetItem(Index: Byte): Byte;
begin
	if Index <= 127 then
		Result := FItems[Index]
	else
		Result := 0;
end;

procedure TOrderList.SetItem(Index: Byte; const Value: Byte);
begin
	if Index <= 127 then
		FItems[Index] := Value;
end;

function TOrderList.GetHighestUsed: Byte;
var
	i: Integer;
begin
	Result := 0; // last pattern to save
	for i := 0 to Module.Info.OrderCount-1 do
		Result := Max(Result, GetItem(i));
end;

procedure TOrderList.Insert(Index: Byte; const Value: Byte);
var
	i: Integer;
begin
	if Index < 127 then
	begin
		for i := 127 downto Index+1 do
			FItems[i] := FItems[i-1];
		FItems[Index] := Value;
	end;
end;

procedure TOrderList.Delete(Index: Byte);
var
	i: Integer;
begin
	if Index < 127 then
	begin
		for i := Index to 127-1 do
			FItems[i] := FItems[i+1];
	end;
	FItems[127] := 0;
end;

// ==========================================================================
// Audio API
// ==========================================================================

// 16-bit integer mixer
//
function AudioCallback(Handle: HSTREAM; Buffer: Pointer; Len: DWord; User: Pointer)
: DWord; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
var
	outStream: ^TArrayOfSmallInt absolute Buffer;
	pos, sampleBlock, samplesTodo: Integer;
	event: TSDL_Event;
begin
	Result := Len;
	FillChar(Buffer^, Len, 0);

	if (Module = nil) or (Module.RenderMode <> RENDER_NONE) then Exit;

	Mixing := True;

	if Length(VUbuffer) <= Len then
		SetLength(VUbuffer, Len + 1024);

	if Module.DisableMixer then
	begin
		ZeroMemory(VUbuffer, Len);
		Mixing := False;
		Exit;
	end;

	pos := 0;
	sampleBlock := Len div 4;

	while sampleBlock > 0 do
	begin
		if (sampleBlock < samplesLeft) then
			samplesTodo := sampleBlock
		else
			samplesTodo := samplesLeft;

		if samplesTodo > 0 then
		begin
			Module.MixSampleBlock(@outStream[pos], samplesTodo);
			pos := pos + (2 * samplesTodo);

			Dec(sampleBlock, samplesTodo);
			Dec(samplesLeft, samplesTodo);
		end
		else
		begin
			if (not Module.DisableMixer) and (Module.PlayMode <> PLAY_STOPPED) then
				Module.IntMusic;
			samplesLeft := Module.samplesPerFrame;
		end;
	end;

	if (not VUhandled) {and (not Module.DisableMixer)} then
	begin
		//VUhandled := False;
		Move(Buffer^, VUbuffer[0], Len);
		event.type_ := SDL_USEREVENT;
		event.user.code := MSG_VUMETER;
		event.user.data1 := Pointer(Len);
		SDL_PushEvent(@event);
	end;

	Mixing := False;
end;

function AudioInit(WinHandle: Cardinal): Boolean;
var
	info: BASS_INFO;
	device: BASS_DEVICEINFO;
	Minbuf: Integer;
	S: AnsiString;
	flags: Cardinal;
begin
	Result := False;
	MainWindow := WinHandle;
	Stream := 0;

	if Options.Audio.Frequency < 8363 then
		Options.Audio.Frequency := 44100;
	outputFreq := Options.Audio.Frequency;

(*	if Assigned(Module) then
		SetLength(Module.MixBuffer, {samplesPerFrame * 2 + 2}
			Round(2 * ((outputFreq * 2.5) / 32.0)) );*)

	{$IFDEF WINDOWS}
	// Speeds up initialization
	BASS_SetConfig(BASS_CONFIG_VISTA_TRUEPOS, 0);
	{$ENDIF}

	if not BASS_Init(Options.Audio.Device, outputFreq,
		BASS_DEVICE_STEREO or BASS_DEVICE_LATENCY or BASS_DEVICE_DMIX,
        WinHandle, nil) then
	begin
		Log(TEXT_ERROR + 'Error initializing audio device!');
		Exit;
	end;

	BASS_GetDeviceInfo(BASS_GetDevice, device);
	BASS_GetInfo(info);

	// Use the recommended minimum buffer length with 1ms margin:
	// Get update period, add the 'minbuf' plus 1ms margin
	BASS_SetConfig(BASS_CONFIG_UPDATEPERIOD, 10);

	// Minimum recommended buffer size
	Minbuf := info.minbuf + 10 + 1;

	if Options.Audio.Buffer = 0 then
		// Default buffer size = 'minbuf' + update period + 1ms extra margin
		BASS_SetConfig(BASS_CONFIG_BUFFER, Minbuf)
	else
		// User set buffer
		BASS_SetConfig(BASS_CONFIG_BUFFER, Options.Audio.Buffer);

	Log('Using audio device: %s', [device.name]);
	Log('%d Hz, 16 bit stereo, %d ms buffer',
		[outputFreq, BASS_GetConfig(BASS_CONFIG_BUFFER)]);
	if (Options.Audio.Buffer > 0) and (Options.Audio.Buffer < Minbuf) then
		Log(TEXT_WARNING + 'audio buffer is below the %d ms recommended minimum', [Minbuf]);

	Stream := BASS_StreamCreate(outputFreq, 2, 0, AudioCallback, @Module);

	if Stream = 0 then
		Log(TEXT_ERROR + 'Error creating audio stream!');

	if not BASS_ChannelPlay(Stream, True) then
	    Log(TEXT_ERROR + 'Error starting audio stream playback!');

	Result := True;

	MSG_VUMETER     := SDL_RegisterEvents(1);
	MSG_ROWCHANGE   := SDL_RegisterEvents(1);
	MSG_ORDERCHANGE := SDL_RegisterEvents(1);
	MSG_TIMERTICK   := SDL_RegisterEvents(1);
end;

procedure AudioClose;
begin
	if Stream <> 0 then
		BASS_StreamFree(Stream);

	BASS_Free;
end;

// ==========================================================================
// Utility
// ==========================================================================

function GetString(var Buf: array of AnsiChar): AnsiString;
var
	i: Integer;
begin
	Result := '';
	for i := 0 to High(Buf) do
	begin
		if Buf[i] = #0 then Exit;
		Result := Result + Buf[i];
	end;
end;

procedure PostMessage(EventType: UInt32);
var
	event: TSDL_Event;
begin
	event.type_ := SDL_USEREVENT;
	event.user.code := EventType;
	event.user.data1 := @Module.PlayPos;
	SDL_PushEvent(@event);
end;

// ==========================================================================
// TNote
// ==========================================================================

procedure TNote.ParseText;

	procedure SetCommand(i: Byte);
	begin
		Command := i;
	end;

	procedure SetExtCommand(i: Byte);
	begin
		Command := $E;
		Parameter := (i shl 4) + (Parameter and 15);
	end;

var
	V: Byte;
begin
	if not Options.Tracker.ITCommands then Exit;

	V := Ord(CmdText[1]) - Ord('A') + 1;
	Parameter := StrToIntDef('$' + Trim(Copy(CmdText, 2, 2)), 0);

	if (Command = 0) and (Parameter > 0) then
		CmdText[1] := 'J';

	case V of

		LETTER_D:
			//if (Parameter shr 4) = $F then
			if (CmdText[2] = 'F') and ((Parameter and 15) <> 0) then
			begin
				// EBx = DFx (Fine volume slide down by x)
				Command := $E;
				Parameter := $B0 + (Parameter and 15);
			end
			else
			//if (Parameter and 15) = $F then
			if (CmdText[3] = 'F') and ((Parameter shr 4) <> 0) then
			begin
				// EAx = DxF (Fine volume slide up by x)
				Command := $E;
				Parameter := Parameter shr 4;
				CmdText[2] := AnsiChar(KeyboardHexNumbers[Parameter + 1]);
				Parameter := $A0 + Parameter;
				Exit;
			end
			else
			begin
				SetCommand($A);
				CmdText[2] := AnsiChar(KeyboardHexNumbers[Parameter shr 4 + 1]);
			end;

		LETTER_S:
			case (Parameter shr 4) of // S0x..SFx
				$1: SetExtCommand($3);
				$2: SetExtCommand($5);
				$3: SetExtCommand($4);
				$4: SetExtCommand($7);
				$6: SetExtCommand($E);
				$B: SetExtCommand($6);
			else
				SetExtCommand(Parameter shr 4);
			end;

		LETTER_Q:
			begin
				SetCommand($E);
				Parameter := $90 + (Parameter and 15);
				CmdText[2] := '0';
			end;

		LETTER_Z:
			SetExtCommand($F);

	else
		Exit;
	end;

	CmdText[3] := AnsiChar(KeyboardHexNumbers[Parameter and 15 + 1]);
end;

procedure TNote.GetText;
var
	V: AnsiChar;
begin
{	if Command >= Length(CmdChars) then
		CmdText := '!!!'
	else}
	CmdText := CmdChars[Command+1] + HexVals[Parameter];

	if Command = 0 then
	begin
		if Parameter = 0 then
			CmdText[1] := '.';	// no command
	end
	else
	if (Command = $E) and (Options.Tracker.ITCommands) then
	begin
		V := CmdText[3];
		case (Parameter shr 4) of
			$0: CmdText := 'S0' + V;
			$1: CmdText := 'FF' + V;
			$2: CmdText := 'EF' + V;
			$3: CmdText := 'S1' + V;
			$4: CmdText := 'S3' + V;
			$5: CmdText := 'S2' + V;
			$6: CmdText := 'SB' + V;
			$7: CmdText := 'S4' + V;
			$8: CmdText := 'S8' + V;
			$9: CmdText := 'Q0' + V;
			$A: CmdText := 'D'  + V + 'F';
			$B: CmdText := 'DF' + V;
			$C: CmdText := 'SC' + V;
			$D: CmdText := 'SD' + V;
			$E: CmdText := 'S6' + V;
			$F:	CmdText := 'Z0' + V;
		end;
	end;
end;

{procedure TNote.Decode(Data: PArrayOfByte);
begin
	Sample    := (Data[0] and $F0) or (Data[2] shr 4);
	Period    := (Data[0] shl 8) or Data[1];
	Command   :=  Data[2] and $0F;
	Parameter :=  Data[3];
end;

function TNote.Encode: Cardinal;
begin
	Result := 0;
end;}

// ==========================================================================
// TChannel
// ==========================================================================

constructor TPTChannel.Create(i: Byte);
begin
	inherited Create;

	n_index := i;
	Paula := TPaulaVoice.Create(outputFreq);
	Reset;
	Enabled := True;
end;

procedure TPTChannel.Reset;
begin
	Note := nil;

	n_start := 0;
	n_wavestart := 0;
	n_loopstart := 0;
	n_volume := 0;
	n_toneportdirec := 0;
	n_vibratopos := 0;
	n_tremolopos := 0;
	n_pattpos := 0;
	n_loopcount := 0;
	n_wavecontrol := 0;
	n_glissfunk := 0;
	n_sampleoffset := 0;
	n_toneportspeed := 0;
	n_vibratocmd := 0;
	n_tremolocmd := 0;
	n_finetune := 0;
	n_funkoffset := 0;
	n_sample := 0;
	n_period := 0;
	n_note := 0;
	n_wantedperiod := 0;
	n_length := 0;
	n_replen := 0;
	n_repend := 0;

	Paula.Sample := 31;
	Paula.QueuedSample := 31;
	Paula.PlayPos := -1;
	Paula.f_OutputFreq := outputFreq;
end;

destructor TPTChannel.Destroy;
begin
	Paula.Free;
	inherited Destroy;
end;

// ==========================================================================
// TPTModule
// ==========================================================================

function TPTModule.CountUsedPatterns: Byte;
var
	i: Integer;
begin
	Result := 0;
	for i := MAX_PATTERNS-1 downto 0 do
	begin
		if not IsPatternEmpty(i) then
		begin
			Result := i;
			Break;
		end;
	end;
	Info.PatternCount := Result;
end;

function TPTModule.IsPatternEmpty(i: Byte): Boolean;
var
	x, y: Integer;
	Note: PNote;
begin
	Result := True;
	if i >= MAX_PATTERNS then Exit;
	for x := 0 to AMOUNT_CHANNELS-1 do
		for y := 0 to 63 do
		begin
			Note := @Notes[i, x, y];
			if (Note.Sample > 0) or (Note.Command > 0)   or
			   (Note.Period > 0) or (Note.Parameter > 0) then
					Exit(False);
		end;
end;

procedure TPTModule.SetTitle(const S: AnsiString);
var
	i: Integer;
begin
	Info.Title := '';
	if Length(S) > 0 then
		for i := 0 to Min(19, Length(S)) do
			Info.Title[i] := S[i+1];
end;

procedure TPTModule.ClearRowVisitTable;
var
	i, j: Integer;
begin
	for i := 0 to MAX_PATTERNS-1 do
		for j := 0 to 63 do
			RenderInfo.RowVisitTable[i,j] := False;
end;

function CheckModType(const buf: AnsiString): TModuleFormat;
begin
	if (buf = 'M.K.') then
	begin
		// ProTracker v1.x, handled as ProTracker v2.x
		Result := FORMAT_MK;
	end
	else
	if (buf = 'M!K!') then
	begin
		// ProTracker v2.x (if >64 patterns)
		Result := FORMAT_MK2;
	end
	else
	if (buf = 'FLT4') then
	begin
		// StarTrekker (4ch), handled as ProTracker v2.x
		Result := FORMAT_FLT4;
	end
	else
	if (buf = '4CHN') then
	begin
		// FastTracker II (4ch), handled as ProTracker v2.x
		Result := FORMAT_4CHN;
	end
	else
	if (buf = 'N.T.') then
	begin
		// NoiseTracker 1.0, handled as ProTracker v2.x
		Result := FORMAT_MK;
	end
	else
	if (buf = 'FEST') then
	begin
		// Special NoiseTracker format (used in music disks?)
		Result := FORMAT_FEST;
	end
	else
	begin
		// may be The Ultimate SoundTracker, 15 samples
		Result := FORMAT_UNKNOWN;
	end;
end;

function TPTModule.SaveToFile(const Filename: String): Boolean;
var
	Data: RawByteString;
	i, j, k, l: Integer;
	c: Cardinal;
//	SavePattern: Boolean;
begin
	Data := '';
	Warnings := False;

	// write song title
	//
	for i := Low(Info.Title) to High(Info.Title) do
		AddVal8(Data, Ord(Info.Title[i]));

	// write sample infos
	//
	for i := 0 to 30 do
	begin
		for j := 0 to 21 do
			AddVal8(Data, Ord(Samples[i].Name[j]));

		AddVal8(Data, Samples[i].Length * 2 shr 9);
		AddVal8(Data, Samples[i].Length * 2 shr 1);
		AddVal8(Data, Samples[i].Finetune and $0F);
		AddVal8(Data, Min(Samples[i].Volume, 64));

		c := Max(Samples[i].LoopLength * 2, 2);
		j := Samples[i].LoopStart * 2;
		if c = 2 then j := 0;

		AddVal8(Data, j shr 9); // tempLoopStart
		AddVal8(Data, j shr 1);
		AddVal8(Data, c shr 9); // tempLoopLength
		AddVal8(Data, c shr 1);
	end;

	AddVal8(Data, Info.OrderCount and $FF);
	AddVal8(Data, $7F); // ProTracker puts 0x7F at this place (restart pos)

	// write orderlist
	//
	for i := 0 to 127 do
		AddVal8(Data, OrderList[i] and $FF);

	// write ID
	//
	if CountUsedPatterns < 64 then
		Data := Data + 'M.K.'
	else
		Data := Data + 'M!K!';	// >64 patterns

	// write pattern data
	//
	j := OrderList.GetHighestUsed;
	Log('Writing %d patterns...', [j+1]);

	for i := 0 to j do
	begin
		for l := 0 to 63 do
		begin
			for k := 0 to AMOUNT_CHANNELS-1 do
			with Notes[i,k,l] do
			begin
				AddVal8(Data, ((Period shr 8) and $0F) or (Sample and $10));
				AddVal8(Data, Period and $FF);
				AddVal8(Data, (Sample shl 4) or (Command and $0F));
				AddVal8(Data, Parameter);
			end;
		end;
	end;

	if j < Info.PatternCount then
		Log(TEXT_WARNING + 'Discarded %d unused patterns!', [Info.PatternCount - j]);

	// write sample data
	//
	for i := 0 to 30 do
	begin
		if (Samples[i].Length >= 2) and (Samples[i].LoopLength <= 2) then
		begin
			// Amiga ProTracker beep fix: zero first word of sample data
			AddVal16(Data, 0);
			k := 2;
		end
		else
			k := 0;
		for j := k to Samples[i].Length*2-1 do
			AddVal8(Data, Samples[i].Data[j]);
	end;

	// write file to disk
	//
	StringToFile(Filename, Data);
	Info.Filename := Filename;

	Log(TEXT_LIGHT + 'Module saved: ' + Filename + '.');
	Log('');

	Result := True;
end;

function ppdecrunch(src, dst, offsetLens: PByte; srcLen, dstLen: uint32; skipBits: Byte): Boolean;
var
	bitsLeft, bitCnt: Byte;
	bufSrc,	dstEnd, bout: PByte;
	x, todo, offBits, offset,
	written, bitBuffer: uint32;

	procedure PP_READ_BITS(nbits: Byte; var nvar: Cardinal);
	begin
		bitCnt := nbits;
		while (bitsLeft < bitCnt) do
		begin
			if (bufSrc < src) then Exit;
			Dec(bufSrc);
			bitBuffer := bitbuffer or (bufSrc^ shl bitsLeft);
			Inc(bitsLeft, 8);
		end;

		nvar := 0;
		Dec(bitsLeft, bitCnt);

		while (bitCnt > 0) do
		begin
			nvar := (nvar shl 1) or (bitBuffer and 1);
			bitBuffer := bitBuffer shr 1;
			Dec(bitCnt);
		end;
	end;

begin
	Result := False;
	if (src = nil) or (dst = nil) or (offsetLens = nil) then Exit;

	bitsLeft  := 0;
	bitBuffer := 0;
	written   := 0;
	bufSrc    := src + srcLen;
	bout      := dst + dstLen;
	dstEnd    := bout;

	PP_READ_BITS(skipBits, x);
	while (written < dstLen) do
	begin
		PP_READ_BITS(1, x);
		if (x = 0) then
		begin
			todo := 1;

			repeat
				PP_READ_BITS(2, x);
				Inc(todo, x);
			until (x <> 3);

			while (todo > 0) do
			begin
				Dec(todo);
				PP_READ_BITS(8, x);
				if (bout <= dst) then
					Exit(False);
				Dec(bout);
				bout^ := Byte(x);
				Inc(written);
			end;

			if (written = dstLen) then
				Break;
		end;

		PP_READ_BITS(2, x);

		offBits := offsetLens[x];
		todo    := x + 2;

		if (x = 3) then
		begin
			PP_READ_BITS(1, x);
			if (x = 0) then offBits := 7;

			PP_READ_BITS(offBits, offset);
			repeat
				PP_READ_BITS(3, x);
				Inc(todo, x);
			until (x <> 7);
		end
		else
			PP_READ_BITS(offBits, offset);

		if ((bout + offset) >= dstEnd) then
			Exit(False);

		while (todo > 0) do
		begin
			Dec(todo);
			x := bout[offset];
			if (bout <= dst) then
				Exit(False);
			Dec(bout);
			bout^ := Byte(x);
			Inc(written);
		end;
	end;
	Result := True;
end;

function TPTModule.LoadFromFile(const Filename: String): Boolean;
var
	os, i, j, patt, row, ch, pattNum: Integer;
	p: PWordArray;
	s: TSample;
	Note: PNote;
	mightBeSTK, mightBeIT, lateVerSTKFlag: Boolean;
	ModFile: TFileAccessor;
	nd: Cardinal;
	bytes: array [0..3] of Byte;
	sFile: AnsiString;

	// powerpacker decrunch
	ppPackLen, ppUnpackLen: uint32;
	ppCrunchData: array [0..3] of Byte;
	ppBuffer, modBuffer: array of Byte;
label
	Done;
begin
	Result := False;
	Warnings := False;

	lateVerSTKFlag := False;
	mightBeIT := False;

	// Read file data
	//
	Log(TEXT_HEAD + 'Loading module: ' + Filename);

	Reset;
	ModFile.Load(Filename);

	Info.BPM := 0;

	// Verify file size
	//
	Info.Filesize := Length(ModFile.Data);
	Info.Filename := '';

	// Determine module type
	//
	sFile := Copy(ModFile.Data, 1, 4); // get header

	if sFile = 'IMPM' then
		mightBeIT := True
	else
	if sFile = 'PX20' then
	begin
		Log(TEXT_ERROR + 'Encrypted PowerPacker module!');
		Exit;
	end
	else
	if sFile = 'PP20' then
	begin
		// decrunch powerpacker module
		Log('File is packed with PowerPacker.');

		ppPackLen := Info.Filesize;
		if (ppPackLen and 3) <> 0 then
		begin
			Log(TEXT_ERROR + 'Load failed: unknown PowerPacker error!');
			Exit;
		end;

		ModFile.SeekTo(ppPackLen - 4);
		ModFile.ReadBytes(PByte(@ppCrunchData[0]), 4);

		ppUnpackLen := (ppCrunchData[0] shl 16) or (ppCrunchData[1] shl 8) or ppCrunchData[2];

		// smallest and biggest possible .MOD
		if (ppUnpackLen < 2108) or (ppUnpackLen > 4195326) then
		begin
			Log(TEXT_ERROR + 'Load failed: not a valid module (incorrect unpacked file size)');
			Exit;
		end;

		SetLength(modBuffer, ppUnpackLen+1);

		ModFile.SeekTo(0);

		ppdecrunch(@ModFile.Data[8+1], @modBuffer[0],
			@ModFile.Data[4+1], ppPackLen-12, ppUnpackLen, ppCrunchData[3]);

		Info.Filesize := ppUnpackLen;
		ModFile.Position := 0;
		SetLength(ModFile.Data, ppUnpackLen+1);
		for i := 0 to ppUnpackLen do
			ModFile.Data[i+1] := AnsiChar(modBuffer[i]);

		//StringToFile('C:\!pp.dat', ModFile.Data);
	end;

	// get normal mod ID
	//
	ModFile.SeekTo(OFFSET_ID);
	ModFile.ReadBytes(PByte(@Info.ID[0]), 4);
	Info.Format := CheckModType(Info.ID);
	mightBeSTK := (Info.Format = FORMAT_UNKNOWN);

	// Import Impulse Tracker module
	// (this will break if a ST module's title begins with "IMPM"!)
	//
	if (Info.Format = FORMAT_UNKNOWN) then
	begin
		if mightBeIT then
		begin
			LoadImpulseTracker(Self, ModFile, SamplesOnly);
			if Options.Tracker.ITCommands then
				GetAllNoteTexts;
			goto Done;
		end
		else
		if Pos('p61', LowerCase(Filename)) > 0 then
		begin
			if not SamplesOnly then
			begin
				sFile := ExtractFileName(Filename);
				sFile := StringReplace(sFile, 'p61.', '', [rfIgnoreCase]);
				sFile := ChangeFileExt(sFile, '');
				SetTitle(sFile);
			end;
			LoadThePlayer(Self, ModFile, SamplesOnly);
			if Options.Tracker.ITCommands then
				GetAllNoteTexts;
			goto Done;
		end;
	end
	else
	if ((Info.Filesize < MODFILESIZE_MIN) or (Info.Filesize > MODFILESIZE_MAX)) then
	begin
		Log(TEXT_ERROR + 'Load failed: Invalid filesize.');
		Exit;
	end;

	// Read song title
	//
	ModFile.SeekTo(OFFSET_SONGTITLE);
	ModFile.ReadBytes(PByte(@Info.Title[0]), 20);

	//ModFile.SeekTo(OFFSET_SAMPLEINFO);

	for i := 0 to 30 {High(Samples)-1} do
	begin
		if SamplesOnly then
		begin
			s := TImportedSample.Create;
			ImportInfo.Samples.Add(TImportedSample(s));
		end
		else
			s := Samples[i];

		if (mightBeSTK) and (i > 14) then
		begin
			s.LoopLength := 1;
			Continue;
		end;

		// index 23 of s.text is already zeroed
		//ModFile.ReadBytes(PByte(@s.Name[0]), 22);
		for j := 0 to 21 do
			s.Name[j] := AnsiChar(Max(32, ModFile.Read8));

		s.Length := ModFile.Read16(True);
		if s.Length > 9999 then
			lateVerSTKFlag := True; // Only used if mightBeSTK is set

		if Info.Format = FORMAT_FEST then
			// One more bit of precision, + inverted
			s.Finetune := ((0 - ModFile.Read8 and $1F) div 2)
		else
			s.Finetune := ModFile.Read8 and $0F;

		s.Volume := Min(64, ModFile.Read8);

		s.LoopStart  := ModFile.Read16(True); // repeat
		s.LoopLength := ModFile.Read16(True); // replen

		if (mightBeSTK) and (s.LoopStart > 0) then
			s.LoopStart := s.LoopStart div 2;
		if s.LoopLength < 2 then
			s.LoopLength := 2;

		// fix for poorly converted STK.PTMOD modules.
		if (not mightBeSTK) and ((s.LoopStart + s.LoopLength) > s.Length) then
		begin
			if ((s.LoopStart div 2) + s.LoopLength) <= s.Length then
			begin
				//Debug('%d: fixing illegal sample loop.', [i+1]);
				s.LoopStart := s.LoopStart div 2;
			end
			else
			begin
				// loop points are still illegal, deactivate loop
				//Debug('%d: disabling illegal sample loop.', [i+1]);
				s.LoopStart  := 0;
				s.LoopLength := 2;
			end;
		end;

		if mightBeSTK then
		begin
			//Debug('%d might be STK.', [i+1]);
			if s.LoopLength > 2 then
			begin
				j := s.LoopStart;
				s.Length       := s.Length - s.LoopStart;
				s.LoopStart    := 0;
				s.tmpLoopStart := j;
			end;

			// No finetune in STK/UST
			s.Finetune := 0;
		end;
	end;

	// STK 2.5 had loopStart in words, not bytes. Convert if late version STK.
	if mightBeSTK and lateVerSTKFlag then
	begin
		//Debug('%d Converting sample loops from STK.', [i+1]);
		for i := 0 to 15 do
		begin
			if SamplesOnly then
				s := ImportInfo.Samples[i]
			else
				s := Samples[i];

			if s.LoopStart > 2 then
			begin
				s.Length := s.Length - s.tmpLoopStart;
				s.tmpLoopStart := s.tmpLoopStart * 2;
			end;
		end;
	end;

	// Read orderlist and find amount of patterns in file
	//
	//ModFile.SeekTo(950);
	Info.OrderCount := Integer(ModFile.Read8);

	if Info.OrderCount > 127 then // fixes beatwave.mod (129 orders) and other weird MODs
	begin
		if Info.OrderCount > 129 then
		begin
			Log(TEXT_ERROR + 'Load failed: not a valid .MOD file (NumOrders > 127)');
			Exit;
		end
		else
			Info.OrderCount := 127;
	end
	else
	if Info.OrderCount = 0 then
	begin
		Log(TEXT_ERROR + 'Load failed: not a valid .MOD file (NumOrders = 0)');
		Exit;
	end;

	Info.RestartPos := ModFile.Read8;

	if (mightBeSTK) and ((Info.RestartPos = 0) or (Info.RestartPos > 220)) then
	begin
		Log(TEXT_ERROR + 'Load failed: not a valid .MOD file');
		Exit;
	end;

	if mightBeSTK then
	begin
		// If we're still here at this point and the mightBeSTK flag is set,
		// then it's definitely a proper The Ultimate SoundTracker (STK) module.
		Info.Format := FORMAT_STK;
		Log('Format: Ultimate SoundTracker');

		if Info.RestartPos = 120 then
			Info.RestartPos := 125
		else
		begin
			if Info.RestartPos > 239 then
				Info.RestartPos := 239;
			// max BPM: 14536 (there was no clamping originally, sick!)
			Info.BPM := Round(1773447 / ((240 - Info.RestartPos) * 122));
			SetTempo(Info.BPM);
		end;
	end
	else
	if (Info.ID = 'M.K.') then
		Log('Format: ProTracker 1.x/2.x (M.K.)')
	else
	if (Info.ID = 'M!K!') then
		Log('Format: ProTracker 2.x (M!K!)')
	else
	if (Info.ID = 'FLT4') then
		Log('Format: StarTrekker (FLT4)')
	else
	if (Info.ID = '4CHN') then
		Log('Format: FastTracker II (4CHN)')
	else
	if (Info.ID = 'N.T.') then
		Log('Format: NoiseTracker 1.0 (N.T.)')
	else
	if (Info.ID = 'FEST') then
		Log('Format: NoiseTracker (alt) (FEST)')
	else
		Log('Format: Unknown');


	Info.PatternCount := 0;
	for i := 0 to 127 do
	begin
		OrderList[i] := ModFile.Read8;
		if OrderList[i] > Info.PatternCount then
			Info.PatternCount := OrderList[i];
	end;

//	Inc(Info.PatternCount);
	if Info.PatternCount > MAX_PATTERNS then
	begin
		Log(TEXT_ERROR + 'Load failed: not a valid .MOD file (NumPatterns=%d > 100)', [Info.PatternCount]);
		Exit;
	end;

	if Info.Format <> FORMAT_STK then // The Ultimate SoundTracker MODs doesn't have this tag
		ModFile.Skip(4); // We already read/tested the tag earlier, skip it

	// Load pattern data
	//
	Warnings := False;

	for patt := 0 to Info.PatternCount do
	begin
		for row := 0 to 63 do
		begin
			for ch := 0 to AMOUNT_CHANNELS-1 do
			begin
				note := @Notes[patt, ch, row];

				bytes[0] := ModFile.Read8;
				bytes[1] := ModFile.Read8;
				bytes[2] := ModFile.Read8;
				bytes[3] := ModFile.Read8;

				note.Period    := ((bytes[0] and $0F) shl 8) or bytes[1];
				note.Sample    :=  (bytes[0] and $F0) or (bytes[2] shr 4); // Don't (!) clamp, the player checks for invalid samples
				note.Command   := bytes[2] and $0F;
				note.Parameter := bytes[3];
				if note.Command = $C then
					note.Parameter := Min(note.Parameter, 64); // todo warn
				note.Text      := GetNoteText(note.Period);

				if Note.Text = High(NoteText) then
					Warnings := True;

				if Info.Format = FORMAT_FEST then
				begin
					// Any Dxx = D00 in FEST modules
					if note.Command = $0D then
						note.Parameter := $00;
				end
				else
				if mightBeSTK then
				begin
					// Convert STK effects to PT effects
					if not lateVerSTKFlag then
					begin
						if note.Command = $01 then
						begin
							// Arpeggio
							note.Command := $00;
						end
						else
						if note.Command = $02 then
						begin
							// Pitch slide
							if (note.Parameter and $F0) <> 0 then
							begin
								note.Command := $02;
								note.Parameter := note.Parameter shr 4;
							end
							else
							if (note.Parameter and $0F) <> 0 then
							begin
								note.Command := $01;
							end;
						end;
					end;

					// Volume slide/pattern break
					if note.Command = $0D then
					begin
						if note.Parameter = 0 then
							note.Command := $0D
						else
							note.Command := $0A;
					end;
				end
				else
				if Info.Format = FORMAT_4CHN then // 4CHN != PT MOD
				begin
					// Remove FastTracker II 8xx/E8x panning commands if present
					if note.Command = $08 then
					begin
						// 8xx
						note.Command   := 0;
						note.Parameter := 0;
					end
					else
					if (note.Command = $0E) and ((note.Parameter shr 4) = $08) then
					begin
						// E8x
						note.Command   := 0;
						note.Parameter := 0;
					end;

					// Remove F00, FastTracker II didn't use F00 as STOP in .MOD
					if (note.Command = $0F) and (note.Parameter = $00) then
					begin
						note.Command   := 0;
						note.Parameter := 0;
					end;
				end;

				note.GetText;

			end; // channel
		end; // row
	end; // pattern

	if Warnings then
		Log(TEXT_WARNING + 'Module contains notes above B-3!');

	// Load sample data
	//
	//	ModFile.SeekTo(OFFSET_PATTERNS + (Info.PatternCount * 1024));
	if Info.Format = FORMAT_STK then
		os := 15
	else
		os := 31;

	//Log('%d samples and %d patterns.', [os, Info.PatternCount+1]);

	for i := 0 to os-1 do
	begin
		if SamplesOnly then
			s := ImportInfo.Samples[i]
		else
			s := Samples[i];

		if (mightBeSTK) and (s.LoopLength > 2) then
		begin
			ModFile.Skip(s.tmpLoopStart * 2);
			j := (s.Length - (s.LoopStart)) * 2;
			//Debug('Read STK sample %d, offset %d, %d bytes', [i+1, ModFile.Position, j]);
			s.LoadData(ModFile, j);
		end
		else
		if s.Length > 0 then
		begin
			//Log('Read sample %d, offset %d, %d bytes', [i+1, ModFile.Position, s.Length * 2]);
			s.LoadData(ModFile, s.Length * 2);
		end;

		//TODO FIXME
		// fix illegal loop length (f.ex. from "Fasttracker II" .MODs)
		if (s.LoopLength <= 2) then
		begin
			s.LoopLength := 1;
			// if no loop, zero first two samples of data to prevent "beep"
			if (s.Length >= 2) then
			begin
				s.Data[0] := 0;
				s.Data[1] := 0;
			end;
		end;

	end;

Done:
	Modified := False;

	CalculatePans(StereoSeparation);
	IndexSamples;

	CurrentSpeed := 6;
	if Info.BPM = 0 then
	begin
		Info.BPM := 125;
		SetTempo(Info.BPM);
	end;

	Result := True;
	Info.Filename := Filename;

	if not Warnings then
		Log(TEXT_LIGHT + 'Load success.')
	else
		Log(TEXT_ERROR + 'Loaded with errors/warnings.');

	Log('');

	if Stream <> 0 then
		BASS_ChannelPlay(Stream, True);
end;

procedure TPTModule.ClearAllNoteTexts;
var
	patt, ch, row: Integer;
begin
	for patt := 0 to MAX_PATTERNS-1 do
	for ch := 0 to AMOUNT_CHANNELS-1 do
	for row := 0 to 63 do
		Notes[patt, ch, row].CmdText := CHR_3PERIODS;
end;

procedure TPTModule.GetAllNoteTexts;
var
	patt, ch, row: Integer;
	Note: PNote;
begin
	if not Options.Tracker.ITCommands then Exit;

	for patt := 0 to MAX_PATTERNS-1 do
	for ch := 0 to AMOUNT_CHANNELS-1 do
	for row := 0 to 63 do
	begin
		Note := @Notes[patt, ch, row];
		if (Note.Command <> 0) or (Note.Parameter <> 0) then
			Note.GetText;
	end;
end;

procedure TPTModule.RepostChanges;
begin
	if RenderMode = RENDER_NONE then
	begin
		PostMessage(MSG_ORDERCHANGE);
		PostMessage(MSG_ROWCHANGE);
	end;
end;

procedure TPTModule.SetModified(B: Boolean = True; Force: Boolean = False);
begin
	if Assigned(OnModified) then
		OnModified(B, Force);
	Modified := B;
end;

constructor TPTModule.Create(aSamplesOnly: Boolean);
var
	i: Integer;
begin
	inherited Create;

	OnFilter := nil;
	OnSpeedChange := nil;
	OnPlayModeChange := nil;

	with EmptyNote do
	begin
		Sample := 0;
		Period := 0;
		Command := 0;
		Parameter := 0;
		Text := 0;
		CmdText := CHR_3PERIODS;
	end;
	ClearAllNoteTexts;

	SamplesOnly := aSamplesOnly;
	ImportInfo.Samples := TObjectList<TImportedSample>.Create(True);
	Samples := TObjectList<TSample>.Create(True);

	Warnings := False;
	Modified := False;

	PreventClipping := True;
	UseBlep := True;
	RenderMode := RENDER_NONE;

	Info.OrderCount := 1;
	Info.PatternCount := 0;
	Info.Tempo := 6;
	Info.Filename := '';

	DisableMixer := True;

	for i := 0 to 31 do
		Samples.Add(TSample.Create);
	IndexSamples;

	for i := 0 to AMOUNT_CHANNELS-1 do
		Channel[i] := TPTChannel.Create(i);

	if not SamplesOnly then
	begin
		Info.BPM := 125;
		CurrentSpeed := 6;

		SetOutputFreq(outputFreq);

		CalculatePans(StereoSeparation);
	end;

	PlayMode := PLAY_STOPPED;
	DisableMixer := False;
end;

procedure TPTModule.SetOutputFreq(Hz: Cardinal);
var
	i: Integer;
begin
	if Hz > 0 then
	begin
		outputFreq := Hz;
		i := Round(2 * ((Hz * 125) / 50 / 32));
		if i mod 2 > 0 then Inc(i);
		{j := samplesPerFrame * 2 + 2;
		if j > i then
		begin
			Log('j!');
			i := j;
		end;}
		SetLength(MixBuffer, i);
//		Log('Mix buffer set to %d samples.', [i]);
	end;

	SetTempo(Info.BPM);

	for i := 0 to AMOUNT_CHANNELS-1 do
		Channel[i].Reset;

	Reset;

	// Amiga 500 RC low-pass filter (R = 360 ohm, C = 0.1uF)
	// hz = 1 / (2pi * R * C)    = ~4421.Hz
	CalcCoeffLossyIntegrator(outputFreq, 4421.0, @FilterLo);

	// Amiga 500 RC high-pass filter (R = 1390 ohm, C = 22uF)
	// hz = 1 / (2pi * R * C)    = ~5.2Hz
	CalcCoeffLossyIntegrator(outputFreq, 5.2, @FilterHi);

	// Amiga 500 Sallen-Key "LED" filter (R1 := 10k ohm, R2 := 10k ohm, C1 := 6800pf, C2 := 3900pf)
	// hz := 1 / (2pi * root(R1 * R2 * C1 * C2))    := ~3090.5Hz
	CalcCoeffLED(outputFreq, 3090.5, @FilterLEDC);
end;

destructor TPTModule.Destroy;
var
	i: Integer;
begin
	Close;

	for i := 0 to AMOUNT_CHANNELS-1 do
		Channel[i].Free;

	{for i := 0 to High(Samples) do
		if Assigned(Samples[i]) then
			Samples[i].Free;}
	Samples.Free;
	ImportInfo.Samples.Free;

	if not SamplesOnly then
		Module := nil;

	inherited Destroy;
end;

procedure TPTModule.Close;
begin
	DisableMixer := True;
	while Mixing do;

	PlayMode := PLAY_STOPPED;

	if Stream <> 0 then
		BASS_ChannelStop(Stream);
end;

procedure TPTModule.IndexSamples;
var
	i: Integer;
begin
	for i := 0 to Samples.Count-1 do
		Samples[i].Index := i + 1;
end;

procedure TPTModule.CalculatePans(percentage: Byte);

	// these are used to create an equal powered panning
	function sinApx(x: Single): Single;
	begin
		x := x * (2.0 - x);
		Result := x * 1.09742972 + x * x * 0.31678383;
	end;

	function cosApx(x: Single): Single;
	begin
		x := (1.0 - x) * (1.0 + x);
		Result := x * 1.09742972 + x * x * 0.31678383;
	end;

var
	scaledPanPos: Byte;
	p: Single;
begin
	if percentage > 100 then
		percentage := 100;

	scaledPanPos := Trunc((percentage * 128) / 100);

	p := (128 - scaledPanPos) * (1.0 / 256.0);
	Channel[0].Paula.PANL := cosApx(p);
	Channel[0].Paula.PANR := sinApx(p);
	Channel[3].Paula.PANL := cosApx(p);
	Channel[3].Paula.PANR := sinApx(p);

	p := (128 + scaledPanPos) * (1.0 / 256.0);
	Channel[1].Paula.PANL := cosApx(p);
	Channel[1].Paula.PANR := sinApx(p);
	Channel[2].Paula.PANL := cosApx(p);
	Channel[2].Paula.PANR := sinApx(p);

	StereoSeparation := percentage;
end;

{$IFDEF DEBUG}
{$R-}
{$ENDIF}

// ==========================================================================
// Effects
// ==========================================================================

procedure TPTModule.UpdateFunk(var ch: TPTChannel);
var
	funkspeed: ShortInt;
begin
	funkspeed := ch.n_glissfunk shr 4;
	if funkspeed > 0 then
	begin
		Inc(ch.n_funkoffset, FunkTable[funkspeed]);
		if (ch.n_funkoffset >= 128) then
		begin
			ch.n_funkoffset := 0;
			Inc(ch.n_wavestart);
			if (ch.n_wavestart >= (ch.n_loopstart + (ch.n_replen * 2))) then
				ch.n_wavestart := ch.n_loopstart;
			Samples[ch.n_sample].Data[ch.n_wavestart] :=
				-1 - Samples[ch.n_sample].Data[ch.n_wavestart];
			SampleChanged[ch.n_sample] := True;
		end;
	end;
end;

procedure TPTModule.SetGlissControl(var ch: TPTChannel);
begin
	ch.n_glissfunk := (ch.n_glissfunk and $F0) or (ch.Note.Parameter and $000F);
end;

procedure TPTModule.SetVibratoControl(var ch: TPTChannel);
begin
	ch.n_wavecontrol := (ch.n_wavecontrol and $F0) or (ch.Note.Parameter and $0F);
end;

procedure TPTModule.SetFineTune(var ch: TPTChannel);
begin
	ch.n_finetune := ch.Note.Parameter and $0F;
end;

procedure TPTModule.JumpLoop(var ch: TPTChannel);
var
	i: Integer;
begin
	if Counter <> 0 then Exit;

	if (ch.Note.Parameter and $0F) = 0 then
	begin
		ch.n_pattpos := PlayPos.Row;
		Exit;
	end;

	if (ch.n_loopcount = 0) then
	begin
		ch.n_loopcount := ch.Note.Parameter and $0F;
	end
	else
	begin
		Dec(ch.n_loopcount);
		if (ch.n_loopcount = 0) then Exit;
	end;

	PBreakPosition  := ch.n_pattpos;
	PBreakFlag := True;

	if RenderMode <> RENDER_NONE then
		for i := PBreakPosition to PlayPos.Row do
			RenderInfo.RowVisitTable[PlayPos.Order, i] := False;
end;

procedure TPTModule.SetTremoloControl(var ch: TPTChannel);
begin
	ch.n_wavecontrol := ((ch.Note.Parameter and $0F) shl 4) or (ch.n_wavecontrol and $0F);
end;

procedure TPTModule.KarplusStrong(var ch: TPTChannel);
begin
	// not implemented
	//Debug('Effect: KarplusStrong');
end;

procedure TPTModule.DoRetrg(var ch: TPTChannel);
begin
	with ch do
	begin
		Paula.SetData(n_sample, n_start); // n_start is increased on 9xx
		Paula.SetLength(n_length);
		Paula.SetPeriod(n_period);
		Paula.RestartDMA;

		// these take effect after the current DMA cycle is done
		Paula.SetData(n_sample, n_loopstart);
		Paula.SetLength(n_replen);
	end;
end;

procedure TPTModule.RetrigNote(var ch: TPTChannel);
begin
	if (ch.Note.Parameter and $0F) <> 0 then
	begin
		if (Counter = 0) then
			if (ch.n_note and $0FFF) <> 0 then
				Exit;

		if (Counter mod (ch.Note.Parameter and $0F)) = 0 then
			DoRetrg(ch);
	end;
end;

procedure TPTModule.VolumeSlide(var ch: TPTChannel);
var
	cmd: Byte;
begin
	cmd := ch.Note.Parameter;
	if (cmd and $F0) = 0 then
	begin
		Dec(ch.n_volume, (cmd and $0F));
		if (ch.n_volume < 0) then
			ch.n_volume := 0;
	end
	else
	begin
		Inc(ch.n_volume, (cmd shr 4));
		if (ch.n_volume > 64) then
			ch.n_volume := 64;
	end;
end;

procedure TPTModule.VolumeFineUp(var ch: TPTChannel);
begin
	if (Counter = 0) then
	begin
		Inc(ch.n_volume, (ch.Note.Parameter and $0F));
		if (ch.n_volume > 64) then
			ch.n_volume := 64;
	end;
end;

procedure TPTModule.VolumeFineDown(var ch: TPTChannel);
begin
	if (Counter = 0) then
	begin
		Dec(ch.n_volume, (ch.Note.Parameter and $0F));
		if (ch.n_volume < 0) then
			ch.n_volume := 0;
	end;
end;

procedure TPTModule.NoteCut(var ch: TPTChannel);
begin
	if (Counter = (ch.Note.Parameter and $0F)) then
		ch.n_volume := 0;
end;

procedure TPTModule.NoteDelay(var ch: TPTChannel);
begin
	if (Counter = (ch.Note.Parameter and $0F)) then
	begin
		if (ch.n_note and $0FFF) <> 0 then
			DoRetrg(ch);
	end;
end;

procedure TPTModule.PatternDelay(var ch: TPTChannel);
begin
	if (Counter = 0) then
	begin
		if (PattDelTime2 = 0) then
			PattDelTime := (ch.Note.Parameter and $0F) + 1;
	end;
end;

procedure TPTModule.FunkIt(var ch: TPTChannel);
begin
	if (Counter = 0) then
	begin
		ch.n_glissfunk := ((ch.Note.Parameter and $0F) shl 4) or (ch.n_glissfunk and $0F);
		if (ch.n_glissfunk and $F0) <> 0 then
			UpdateFunk(ch);
	end;
end;

procedure TPTModule.PositionJump(var ch: TPTChannel);
var
	NewOrder: ShortInt;
begin
	NewOrder :=	ch.Note.Parameter and $7F - 1;
	if NewOrder = -1 then
		NewOrder := Info.OrderCount - 1;
	PlayPos.Order := NewOrder;
	PBreakPosition := 0;
	PosJumpAssert  := True;

	if RenderMode = RENDER_NONE then
		PostMessage(MSG_ORDERCHANGE);
end;

procedure TPTModule.VolumeChange(var ch: TPTChannel);
begin
	ch.n_volume := Min(64, ch.Note.Parameter);
end;

procedure TPTModule.PatternBreak(var ch: TPTChannel);
begin
	PBreakPosition := (((ch.Note.Parameter and $F0) shr 4) * 10) + (ch.Note.Parameter and $0F);
	if (PBreakPosition > 63) then
		PBreakPosition := 0;
	// TODO: PlayPos change?
	PosJumpAssert := True;
end;

procedure TPTModule.SetReplayerBPM(bpm: Byte);
var
	ciaVal: Word;
	f_hz, f_smp: Single;
begin
	if outputFreq = 0.0 then Exit;

	if bpm < 32 then bpm := 32;

	ciaVal := Trunc(1773447 / bpm); // yes, truncate here
	f_hz  := CIA_PAL_CLK / ciaVal;
	f_smp := outputFreq / f_hz;

	samplesPerFrame := Trunc(f_smp + 0.5);

	{$IFDEF DEBUG}
	// Log('Samples per Frame: %d', [samplesPerFrame]);
	{$ENDIF}
end;

procedure TPTModule.SetSpeed(var ch: TPTChannel);
var
	bufsize: Cardinal;
begin
	if (ch.Note.Parameter) = 0 then Exit;

	Counter := 0;

	if (TempoMode <> 0) or ((ch.Note.Parameter) < 32) then
	begin
		CurrentSpeed := ch.Note.Parameter;
		if CurrentSpeed = 0 then
			RenderInfo.HasBeenPlayed := True;
	end
	else
	begin
		CurrentBPM := ch.Note.Parameter;
		SetReplayerBPM(CurrentBPM);
		bufsize := samplesPerFrame * 2 + 2;
		if Length(MixBuffer) < bufsize then
			SetLength(MixBuffer, bufsize);
	end;

	//Log('SetSpeed (%d) samplesPerFrame=%d', [ch.Note.Parameter, samplesPerFrame]);

	if RenderMode = RENDER_NONE then
		if Assigned(OnSpeedChange) then
			OnSpeedChange;
end;

procedure TPTModule.Arpeggio(var ch: TPTChannel);
var
	i: Integer;
	dat: Byte;
	arpPointer: PArrayOfSmallInt;
begin
	dat := Counter mod 3;

	case dat of
		0: begin ch.Paula.SetPeriod(ch.n_period); Exit; end;
		1: dat := (ch.Note.Parameter and $F0) shr 4;
		2: dat := ch.Note.Parameter and $0F;
	end;

	arpPointer := @PeriodTable[37 * ch.n_finetune];
	for i := 0 to 36 do
	begin
		if (ch.n_period >= arpPointer[i]) then
		begin
			ch.Paula.SetPeriod(arpPointer[i + dat]);
			Break;
		end;
	end;
end;

procedure TPTModule.PortaUp(var ch: TPTChannel);
begin
	Dec(ch.n_period, ((ch.Note.Parameter) and LowMask));
	LowMask := $FF;

	if ((ch.n_period and $0FFF) < 113) then
		ch.n_period := (ch.n_period and $F000) or 113;

	ch.Paula.SetPeriod(ch.n_period and $0FFF);
end;

procedure TPTModule.PortaDown(var ch: TPTChannel);
begin
	Inc(ch.n_period, ((ch.Note.Parameter) and LowMask));
	LowMask := $FF;

	if ((ch.n_period and $0FFF) > 856) then
		ch.n_period := (ch.n_period and $F000) or 856;

	ch.Paula.SetPeriod(ch.n_period and $0FFF);
end;

procedure TPTModule.FilterOnOff(var ch: TPTChannel);
begin
	LEDStatus := (ch.Note.Parameter and $01) = 0; // !(ch.n_cmd and $0001);
	if Assigned(OnFilter) then
		OnFilter;
end;

procedure TPTModule.FinePortaUp(var ch: TPTChannel);
begin
	if (Counter = 0) then
	begin
		LowMask := $0F;
		PortaUp(ch);
	end;
end;

procedure TPTModule.FinePortaDown(var ch: TPTChannel);
begin
	if (Counter = 0) then
	begin
		LowMask := $0F;
		PortaDown(ch);
	end;
end;

procedure TPTModule.SetTonePorta(var ch: TPTChannel);
var
	i: Integer;
	note: Word;
	portaPointer: PArrayOfSmallInt;
begin
	note := ch.n_note and $0FFF;
	portaPointer := @PeriodTable[37 * ch.n_finetune];

	i := 0;
	while True do
	begin
		// portaPointer[36] := 0, so i=36 is safe
		if (note >= portaPointer[i]) then
			Break;
		Inc(i);
		if (i >= 37) then
		begin
			i := 35;
			Break;
		end;
	end;

	if ((ch.n_finetune and 8) <> 0) and (i <> 0) then
		Dec(i);

	ch.n_wantedperiod := portaPointer[i];
	ch.n_toneportdirec := 0;

	if (ch.n_period = ch.n_wantedperiod) then
		ch.n_wantedperiod := 0
	else
	if (ch.n_period > ch.n_wantedperiod) then
		ch.n_toneportdirec := 1;
end;

procedure TPTModule.TonePortNoChange(var ch: TPTChannel);
var
	i: Integer;
	portaPointer: PArrayOfSmallInt;
begin
	if (ch.n_wantedperiod <> 0) then
	begin
		if (ch.n_toneportdirec <> 0) then
		begin
			Dec(ch.n_period, ch.n_toneportspeed);
			if (ch.n_period <= ch.n_wantedperiod) then
			begin
				ch.n_period := ch.n_wantedperiod;
				ch.n_wantedperiod := 0;
			end;
		end
		else
		begin
			Inc(ch.n_period, ch.n_toneportspeed);
			if (ch.n_period >= ch.n_wantedperiod) then
			begin
				ch.n_period := ch.n_wantedperiod;
				ch.n_wantedperiod := 0;
			end;
		end;

		if (ch.n_glissfunk and $0F) = 0 then
		begin
			ch.Paula.SetPeriod(ch.n_period);
		end
		else
		begin
			portaPointer := @PeriodTable[37 * ch.n_finetune];

			i := 0;
			while True do
			begin
				// portaPointer[36] := 0, so i=36 is safe
				if (ch.n_period >= portaPointer[i]) then
					Break;
				Inc(i);
				if (i >= 37) then
				begin
					i := 35;
					Break;
				end;
			end;

			ch.Paula.SetPeriod(portaPointer[i]);
		end;
	end;
end;

procedure TPTModule.TonePortamento(var ch: TPTChannel);
begin
	if (ch.Note.Parameter) <> 0 then
		ch.n_toneportspeed := ch.Note.Parameter;

	TonePortNoChange(ch);
end;

procedure TPTModule.VibratoNoChange(var ch: TPTChannel);
var
	vibratoTemp: Byte;
	vibratoData: Word;
begin
	vibratoTemp := (ch.n_vibratopos div 4) and 31;
	vibratoData := ch.n_wavecontrol and 3;

	if (vibratoData = 0) then
	begin
		vibratoData := VibratoTable[vibratoTemp];
	end
	else
	begin
		if (vibratoData = 1) then
		begin
			if (ch.n_vibratopos < 0) then
				vibratoData := 255 - (vibratoTemp * 8)
			else
				vibratoData := vibratoTemp * 8;
		end
		else
			vibratoData := 255;
	end;

	vibratoData := (vibratoData * (ch.n_vibratocmd and $0F)) div 128;

	if (ch.n_vibratopos < 0) then
		vibratoData := ch.n_period - vibratoData
	else
		vibratoData := ch.n_period + vibratoData;

	ch.Paula.SetPeriod(vibratoData);

	Inc(ch.n_vibratopos, ((ch.n_vibratocmd shr 4) * 4));
end;

procedure TPTModule.Vibrato(var ch: TPTChannel);
begin
	if (ch.Note.Parameter) <> 0 then
	begin
		if (ch.Note.Parameter and $0F) <> 0 then
			ch.n_vibratocmd := (ch.n_vibratocmd and $F0) or (ch.Note.Parameter and $0F);

		if (ch.Note.Parameter and $F0) <> 0 then
			ch.n_vibratocmd := (ch.Note.Parameter and $F0) or (ch.n_vibratocmd and $0F);
	end;

	VibratoNoChange(ch);
end;

procedure TPTModule.TonePlusVolSlide(var ch: TPTChannel);
begin
	TonePortNoChange(ch);
	VolumeSlide(ch);
end;

procedure TPTModule.VibratoPlusVolSlide(var ch: TPTChannel);
begin
	VibratoNoChange(ch);
	VolumeSlide(ch);
end;

procedure TPTModule.Tremolo(var ch: TPTChannel);
var
	tremoloTemp: ShortInt;
	tremoloData: SmallInt;
begin
	if (ch.Note.Parameter) <> 0 then
	begin
		if (ch.Note.Parameter and $0F) <> 0 then
			ch.n_tremolocmd := (ch.n_tremolocmd and $F0) or (ch.Note.Parameter and $0F);
		if (ch.Note.Parameter and $F0) <> 0 then
			ch.n_tremolocmd := (ch.Note.Parameter and $F0) or (ch.n_tremolocmd and $0F);
	end;

	tremoloTemp := (ch.n_tremolopos div 4) and 31;
	tremoloData := (ch.n_wavecontrol shr 4) and 3;

	if (tremoloData = 0) then
		tremoloData := VibratoTable[tremoloTemp]
	else
	if (tremoloData = 1) then
	begin
		if (ch.n_vibratopos < 0) then // PT bug, should've been n_tremolopos
			tremoloData := 255 - (tremoloTemp * 8)
		else
			tremoloData := tremoloTemp * 8;
	end
	else
		tremoloData := 255;

	tremoloData := (tremoloData * (ch.n_tremolocmd and $0F)) div 64;

	if (ch.n_tremolopos < 0) then
	begin
		tremoloData := ch.n_volume - tremoloData;
		if (tremoloData < 0) then tremoloData := 0;
	end
	else
	begin
		tremoloData := ch.n_volume + tremoloData;
		if (tremoloData > 64) then tremoloData := 64;
	end;

	ch.Paula.SetVolume(tremoloData);

	Inc(ch.n_tremolopos, (ch.n_tremolocmd shr 4) * 4);
end;

procedure TPTModule.SampleOffset(var ch: TPTChannel);
var
	newOffset: Word;
begin
	if (ch.Note.Parameter) <> 0 then
		ch.n_sampleoffset := ch.Note.Parameter;

	newOffset := ch.n_sampleoffset * 128;
	if (newOffset < ch.n_length) then
	begin
		Dec(ch.n_length, newOffset);
		Inc(ch.n_start, (newOffset * 2));
	end
	else
		ch.n_length := 1; // this must NOT be set to 0! 1 is the correct value
end;

procedure TPTModule.E_Commands(var ch: TPTChannel);
begin
	case (ch.Note.Parameter shr 4) of
		$00: FilterOnOff(ch);
		$01: FinePortaUp(ch);
		$02: FinePortaDown(ch);
		$03: SetGlissControl(ch);
		$04: SetVibratoControl(ch);
		$05: SetFineTune(ch);
		$06: JumpLoop(ch);
		$07: SetTremoloControl(ch);
		$08: KarplusStrong(ch);
		$09: RetrigNote(ch);
		$0A: VolumeFineUp(ch);
		$0B: VolumeFineDown(ch);
		$0C: NoteCut(ch);
		$0D: NoteDelay(ch);
		$0E: PatternDelay(ch);
		$0F: FunkIt(ch);
	end;
end;

procedure TPTModule.CheckMoreEffects(var ch: TPTChannel);
begin
	if not Options.Audio.EditorInvertLoop then
		UpdateFunk(ch);

	case ch.Note.Command of
		$09: SampleOffset(ch);
		$0B: PositionJump(ch);
		$0D: PatternBreak(ch);
		$0E: E_Commands(ch);
		$0F: SetSpeed(ch);
		$0C: VolumeChange(ch);
	else
		ch.Paula.SetPeriod(ch.n_period);
	end;
end;

procedure TPTModule.CheckEffects(var ch: TPTChannel);
begin
	UpdateFunk(ch);

	if (ch.Note.Command <> 0) or (ch.Note.Parameter <> 0) then
	begin
		case (ch.Note.Command and $0F) of
			$00: Arpeggio(ch);
			$01: PortaUp(ch);
			$02: PortaDown(ch);
			$03: TonePortamento(ch);
			$04: Vibrato(ch);
			$05: TonePlusVolSlide(ch);
			$06: VibratoPlusVolSlide(ch);
			$0E: E_Commands(ch);
			$07: begin
					ch.Paula.SetPeriod(ch.n_period);
					Tremolo(ch);
				 end;
			$0A: begin
					ch.Paula.SetPeriod(ch.n_period);
					VolumeSlide(ch);
				 end;
		else
			ch.Paula.SetPeriod(ch.n_period);
		end;
	end;

	ch.Paula.SetVolume(ch.n_volume);
end;

procedure TPTModule.SetPeriod(var ch: TPTChannel);
var
	i: Integer;
begin
	for i := 0 to 36 do
	begin
		// PeriodTable[36] = 0, so i=36 is safe
		if (ch.n_note >= PeriodTable[i]) then Break;
	end;

	// BUG: yes it's 'safe' if i=37 because of padding at the end of period table
	ch.n_period := PeriodTable[(37 * ch.n_finetune) + i];

	//if ((ch.n_cmd and $0FF0) <> $0ED0) then // no note delay
	if (ch.Note.Command <> $E) or ((ch.Note.Parameter and $F0) <> $D0) then
	begin
		if ((ch.n_wavecontrol and $04) = 0) then ch.n_vibratopos := 0;
		if ((ch.n_wavecontrol and $40) = 0) then ch.n_tremolopos := 0;

		// pt2play <1.3
		if (ch.n_length = 0) then
		begin
			ch.n_loopstart := 0;
			ch.n_length := 1; // this must NOT be set to 0! 1 is the correct value
			ch.n_replen := 1;
		end;

		with ch.Paula do
		begin
			SetLength(ch.n_length);
			SetData(ch.n_sample, ch.n_start);

			// pt2play 1.3
			{if ch.n_start = 0 then
			begin
				ch.n_loopstart := 0;
				SetLength(1);
				ch.n_replen := 1;
			end;}

			SetPeriod(ch.n_period);
			RestartDMA;
		end;
	end;

	CheckMoreEffects(ch);
end;

{$IFDEF DEBUG}
{$R+}
{$ENDIF}

// ==========================================================================
// Playback
// ==========================================================================

procedure TPTModule.PlayVoice(var ch: TPTChannel);
var
	sample: Byte;
	srepeat: Word;
begin
	if (ch.n_note = 0) and (ch.Note.Command = 0) and (ch.Note.Parameter = 0) then
		ch.Paula.SetPeriod(Word(ch.n_period));

	ch.Note := @Notes[PlayPos.Pattern, ch.n_index, PlayPos.Row];
	ch.n_note := ch.Note.Period and $0FFF;

	// SAFETY BUG FIX: don't handle sample-numbers >31
	sample := ch.Note.Sample;
	if (sample >= 1) and (sample <= 31) then
	begin
		Dec(sample);

		ch.n_sample   := sample;
		ch.n_start    := 0; // Data[0]
		ch.n_finetune := Samples[sample].Finetune;
		ch.n_volume   := Samples[sample].Volume;
		ch.n_length   := Samples[sample].Length;
		ch.n_replen   := Samples[sample].LoopLength;
		srepeat       := Samples[sample].LoopStart;

		ch.Paula.Sample := sample;
		Samples[sample].Age := 3;

		if (srepeat > 0) then
		begin
			ch.n_loopstart := ch.n_start + (srepeat * 2);
			ch.n_wavestart := ch.n_loopstart;
			ch.n_length    := srepeat + ch.n_replen;
		end
		else
		begin
			ch.n_loopstart := ch.n_start;
			ch.n_wavestart := ch.n_start;
		end;
	end;

	if ch.n_note > 0 then
	begin
		case ch.Note.Command of

			$3, $5:
			begin
				SetTonePorta(ch);
				CheckMoreEffects(ch);
			end;

			$9:
			begin
				CheckMoreEffects(ch);
				SetPeriod(ch);
			end;

			$E:
			begin
				if (ch.Note.Parameter and $F0) = $50 then
					SetFineTune(ch);
				SetPeriod(ch);
			end;
		else
			SetPeriod(ch);
		end;
	end
	else
		CheckMoreEffects(ch);
end;

procedure TPTModule.NextPosition;
var
	NewOrder: Byte;
begin
	PlayPos.Row    := PBreakPosition;
	PBreakPosition := 0;
	PosJumpAssert  := False;

	if PlayMode = PLAY_SONG then
	begin
		NewOrder := (PlayPos.Order + 1) and $7F;
		if (NewOrder >= Info.OrderCount) then
		begin
			NewOrder := 0;
			RenderInfo.HasBeenPlayed := True;
		end;

		PlayPos.Order := NewOrder;
		PlayPos.Pattern := OrderList[NewOrder];

		if RenderMode = RENDER_NONE then
			PostMessage(MSG_ORDERCHANGE);
	end;
end;

// called (SongBPM/2.5) times a second (duration: 1000/(SongBPM/2.5) milliseconds)
//
procedure TPTModule.IntMusic;
var
	i: Integer;
begin
	if RenderMode <> RENDER_NONE then
	begin
		if RenderMode <> RENDER_SAMPLE then
		begin
			RenderInfo.HasBeenPlayed := False;
			if Counter = 0 then
			begin
				{if PlayPos.Order < 0 then
					RenderInfo.RowVisitTable[Info.OrderCount - 1, PlayPos.Row] := True
				else}
					RenderInfo.RowVisitTable[PlayPos.Order, PlayPos.Row] := True;
			end;
		end;
	end;

	Inc(Counter);

	if Counter < CurrentSpeed then
	begin
		CheckEffects(Channel[0]);
		CheckEffects(Channel[1]);
		CheckEffects(Channel[2]);
		CheckEffects(Channel[3]);
		if PosJumpAssert then
			NextPosition;
		Exit;
	end;

	Counter := 0;

	if PattDelTime2 = 0 then
	begin
		for i := 0 to AMOUNT_CHANNELS-1 do
		begin
			PlayVoice(Channel[i]);
			Channel[i].Paula.SetVolume(Channel[i].n_volume);
			// these take effect after the current DMA cycle is done
			Channel[i].Paula.SetData(Channel[i].n_sample, Channel[i].n_loopstart);
			Channel[i].Paula.SetLength(Channel[i].n_replen);
		end;
	end
	else
	begin
		CheckEffects(Channel[0]);
		CheckEffects(Channel[1]);
		CheckEffects(Channel[2]);
		CheckEffects(Channel[3]);
	end;

	Inc(PlayPos.Row);

	if PattDelTime <> 0 then
	begin
		PattDelTime2 := PattDelTime;
		PattDelTime  := 0;
	end;

	if PattDelTime2 <> 0 then
	begin
		Dec(PattDelTime2);
		if PattDelTime2 <> 0 then
			Dec(PlayPos.Row);
	end;

	if PBreakFlag then
	begin
		if RenderMode = RENDER_SAMPLE then
		begin
			Stop;
			Exit;
		end;
		PlayPos.Row := PBreakPosition;
		PBreakPosition := 0;
		PBreakFlag := False;
	end;

	if (PosJumpAssert) or (PlayPos.Row > 63) then
		NextPosition
	else
	if RenderMode = RENDER_NONE then
	begin
        PostMessage(MSG_ROWCHANGE);
	end
	else
	if PattDelTime2 = 0 then
	begin
		if RenderMode = RENDER_SAMPLE then
		begin
			Inc(RenderInfo.RowsRendered);
			if RenderInfo.RowsRendered > RenderInfo.LastRow then
			begin
				Stop;
				Exit;
			end;
		end
		else
		if RenderInfo.RowVisitTable[PlayPos.Order, PlayPos.Row] then
		begin
			// rendermode <> none
			Inc(RenderInfo.TimesLooped);
			//Log('STOP (Loop=%d) Ord=%d Patt=%d Row=%d', [RenderInfo.TimesLooped, PlayPos.Order, PlayPos.Pattern, PlayPos.Row]);
			if (RenderMode = RENDER_LENGTH) and (RenderInfo.TimesLooped > RenderInfo.LoopsWanted) then
				Stop
			else
				ClearRowVisitTable;
		end;
	end;
end;

procedure TPTModule.SetTempo(bpm: Word);
begin
	if (bpm < 1) then Exit;

	CurrentBPM := bpm;
	SetReplayerBPM(CurrentBPM);

	if RenderMode = RENDER_NONE then
		if Assigned(OnSpeedChange) then
			OnSpeedChange;
end;

procedure TPTModule.ApplyAudioSettings;
begin
	NormFactor       := Max(Options.Audio.Amplification, 0.01);
	FilterHighPass   := Options.Audio.FilterHighPass;
	FilterLowPass    := Options.Audio.FilterLowPass;

	if StereoSeparation <> Options.Audio.StereoSeparation then
	begin
		StereoSeparation := Options.Audio.StereoSeparation;
		CalculatePans(StereoSeparation);
	end;
end;

procedure TPTModule.Reset;
var
	i: Integer;
begin
	ClearLossyIntegrator(@FilterLo);
	ClearLossyIntegrator(@FilterHi);
	ClearLEDFilter(@FilterLED);

	ApplyAudioSettings;

	PattDelTime    := 0;
	PattDelTime2   := 0;
	PBreakPosition := 0;
	PosJumpAssert  := False;
	PBreakFlag     := False;
	LowMask        := $FF;

	if Options.Audio.CIAmode then
		TempoMode := 1
	else
		TempoMode := 0;

	LEDStatus := False;
	Counter := CurrentSpeed;

	if RenderMode <> RENDER_NONE then
		ClearRowVisitTable;

	for i := 0 to 30 do
	begin
		Samples[i].Age := -1;
	end;

	for i := 0 to AMOUNT_CHANNELS-1 do
	begin
		Channel[i].Reset;
		ZeroBlep(@Blep[i]);
		ZeroBlep(@BlepVol[i]);
	end;
end;

procedure TPTModule.InitPlay(pattern: Byte);
var
	i: Integer;
begin
	Reset;

	for i := 0 to AMOUNT_CHANNELS-1 do
		Channel[i].Note := @Notes[pattern, i, 0];

	RenderInfo.SamplesRendered := 0;
	RenderInfo.RowsRendered := 0;
	RenderInfo.OrderChanges := 0;
	RenderInfo.TimesLooped := 0;
	RenderInfo.HasBeenPlayed := False;
	RenderInfo.Canceled := False;

	if RenderMode = RENDER_LENGTH then Exit;

	DisableMixer := False;
	PlayStarted := Now;

	if Assigned(OnPlayModeChange) then
		OnPlayModeChange;
end;

procedure TPTModule.PlayPattern(pattern: Byte; row: Byte = 0);
begin
	Stop;

	PlayPos.Pattern := pattern;
	PlayPos.Row     := row;

	if RenderMode = RENDER_NONE then
		PostMessage(MSG_ROWCHANGE);

	PlayMode := PLAY_PATTERN;
	InitPlay(pattern);
end;

procedure TPTModule.Play(order: Byte = 0; row: Byte = 0);
begin
	Stop;

	PlayPos.Pattern := OrderList[order];
	PlayPos.Row := row;
	PlayPos.Order := order;

	PlayMode := PLAY_SONG;
	InitPlay(OrderList[0]);

	if RenderMode = RENDER_NONE then
		PostMessage(MSG_ROWCHANGE);
end;

procedure TPTModule.Stop;
var
	i: Integer;
begin
	DisableMixer := True;
	RenderInfo.HasBeenPlayed := True;

	if RenderMode = RENDER_NONE then
		while Mixing do;

	PlayMode := PLAY_STOPPED;

	if RenderMode = RENDER_NONE then
		if Assigned(OnPlayModeChange) then
			OnPlayModeChange;

	for i := 0 to AMOUNT_CHANNELS-1 do
	begin
		Channel[i].Paula.Kill;
		Channel[i].Note := @Notes[OrderList[0], i, 0];
	end;

	Counter := 0;
	DisableMixer := False;
end;

procedure TPTModule.Pause(Pause: Boolean);
begin
	DisableMixer := Pause;
	if Pause then
		while Mixing do;
end;

procedure TPTModule.PlayNote(Note: PNote; Chan: Byte);
var
	sample: TSample;
	srepeat: Word;
	ch: TPTChannel;
begin
	if (Chan >= AMOUNT_CHANNELS) then Exit;
	if not (Note.Sample in [1..31]) then Exit;

	ch := Channel[Chan];
	if not ch.Enabled then Exit;

	sample := Samples[Note.Sample-1];
	if sample.Length = 0 then
	begin
		ch.Paula.Kill;
		Exit;
	end;

	DisableMixer := True;

	ch.Note := Note;
	ch.n_note := Note.Period and $0FFF;

	ch.n_sample   := Note.Sample-1;
	ch.n_start    := 0; // Data[0]
	ch.n_period   := PeriodTable[(37 * sample.Finetune) + GetPeriodTableOffset(Note.Period)];
	ch.n_finetune := sample.Finetune;
	ch.n_volume   := sample.Volume;
	ch.n_length   := sample.Length;
	ch.n_replen   := sample.LoopLength;
	srepeat       := sample.LoopStart;

	if (srepeat > 0) then
	begin
		ch.n_loopstart := ch.n_start + (srepeat * 2);
		ch.n_wavestart := ch.n_loopstart;
		ch.n_length    := srepeat + ch.n_replen;
	end
	else
	begin
		ch.n_loopstart := ch.n_start;
		ch.n_wavestart := ch.n_start;
	end;

	CheckMoreEffects(ch); // parse volume fx

	with ch do
	begin
		Paula.PlayPos := -1;

		Paula.SetData(n_sample, n_start);
		Paula.SetLength(n_length);
		Paula.SetPeriod(n_period);
		Paula.SetVolume(n_volume);
		Paula.RestartDMA;

		// these take effect after the current DMA cycle is done
		Paula.SetData(n_sample, n_loopstart);
		Paula.SetLength(n_replen);
	end;

	DisableMixer := False;
end;

procedure TPTModule.PlaySample(_note, _sample, _channel: Byte; _volume: ShortInt = -1;
	_start: Integer = 0; _length: Integer = 0);
var
	S: TSample;
	srepeat: Word;
begin
	if (_channel >= AMOUNT_CHANNELS) then Exit;
	if not (_sample in [1..32]) then Exit;

	Dec(_sample);
	S := Samples[_sample];

	with Channel[_channel] do
	begin
		if not Enabled then Exit;

		DisableMixer := True;

		n_period   := PeriodTable[(37 * S.Finetune) + _note];
		n_sample   := _sample;
		n_start    := _start;
		n_finetune := S.Finetune;
		if _volume >= 0 then
			n_volume := _volume
		else
			n_volume   := S.Volume;
		if _length = 0 then
			n_length   := S.Length
		else
			n_length   := _length;

		n_replen   := S.LoopLength;
		srepeat    := S.LoopStart;

		Paula.PlayPos := -1;

		if n_length = 0 then
		begin
			Paula.Kill;
			DisableMixer := False;
			Exit;
		end;

		// just play a section of sample, nonlooped
		if _length > 0 then
		begin
			//srepeat := 0;
			n_loopstart := 0;
			n_wavestart := n_start;
			n_replen := 1;
		end
		else
		if srepeat > 0 then
		begin
			n_loopstart := n_start + (srepeat * 2);
			n_wavestart := n_loopstart;
			n_length    := srepeat + n_replen;
		end
		else
		begin
			n_loopstart := n_start;
			n_wavestart := n_start;
		end;

		Paula.SetData(_sample, n_start);
		Paula.SetLength(n_length);
		Paula.SetPeriod(n_period);
		Paula.SetVolume(n_volume);
		Paula.RestartDMA;

		// these take effect after the current DMA cycle is done
		Paula.SetData(_sample, n_loopstart);
		Paula.SetLength(n_replen);
	end;

	DisableMixer := False;
end;

procedure TPTModule.MixSampleBlock(streamOut: Pointer; numSamples: Cardinal);
var
	i: Integer;
	j: Word;
	sndOut: ^TArrayOfSmallInt absolute streamOut;
	Amp, tempSample, tempVolume: Single;
	outSample: array [0..1] of Single;
	masterBufferL, masterBufferR: array of Single;
	v: TPaulaVoice;
	bSmp, bVol: PBlep;
	Sam: TSample;
const
	SCALER = 1.0 / 128.0;
begin
	ClippedSamples := 0;
	Amp := -32767.0 / NormFactor;

	if Length(masterBufferL) < (numSamples + 2) then
	begin
		SetLength(masterBufferL, numSamples + 2);
		SetLength(masterBufferR, numSamples + 2);
	end;

	{$R-}

	for i := 0 to AMOUNT_CHANNELS-1 do
	begin
		v := Channel[i].Paula;

		//if UseBlep then
		begin
			bSmp := @Blep[i];
			bVol := @BlepVol[i];
		end;

		if (Channel[i].Enabled) and (v.DELTA > 0.0) then
		begin
			for j := 0 to numSamples-1 do
			begin
				if v.DMA_DAT = nil then
				begin
					tempSample := 0.0;
					tempVolume := 0.0;
				end
				else
				begin
					tempSample := v.DMA_DAT[v.DMA_POS] * SCALER;
					tempVolume := v.SRC_VOL;
				end;

				if UseBlep then
				begin
					if (tempSample <> bSmp.lastValue) then
					begin
						if ((v.LASTDELTA > 0.0) and (v.LASTDELTA > v.LASTFRAC)) then
							BlepAdd(bSmp, v.LASTFRAC / v.LASTDELTA, bSmp.lastValue - tempSample);
						bSmp.lastValue := tempSample;
					end;

					if (tempVolume <> bVol.lastValue) then
					begin
						BlepAdd(bVol, 0.0, bVol.lastValue - tempVolume);
						bVol.lastValue := tempVolume;
					end;

					if (bSmp.samplesLeft > 0) then
						tempSample := tempSample + BlepRun(bSmp);
					if (bVol.samplesLeft > 0) then
						tempVolume := tempVolume + BlepRun(bVol);
				end;

				tempSample := tempSample * tempVolume;
				masterBufferL[j] := masterBufferL[j] + (tempSample * v.PANL);
				masterBufferR[j] := masterBufferR[j] + (tempSample * v.PANR);

				v.FRAC := v.FRAC + v.DELTA;
				if v.FRAC >= 1.0 then
				begin
					v.FRAC := v.FRAC - 1.0;
					v.LASTFRAC := v.FRAC;
					v.LASTDELTA := v.DELTA;

					Sam := Samples[v.Sample];

					Inc(v.DMA_POS);
					if v.DMA_POS >= v.DMA_LEN then
					begin
						v.DMA_POS := 0;

						// re-fetch Paula register values now
						v.DMA_LEN := v.SRC_LEN;
						v.DMA_DAT := @v.SRC_DAT[0];

						{if v.Sample <> v.QueuedSample then
						begin}
							v.Sample := v.QueuedSample;
							//Samples[v.Sample].Age := 5;
						//end;

						if Sam.LoopLength <= 2 then
							v.PlayPos := -1
						else
							v.PlayPos := v.QueuedOffset;
					end
					else
					if v.PlayPos >= 0 then
						Inc(v.PlayPos);

				end;
			end;
		end;
	end;

	for j := 0 to numSamples-1 do
	begin
		outSample[0] := masterBufferL[j];
		outSample[1] := masterBufferR[j];

		if FilterLowPass then
			LossyIntegrator(@FilterLo, @outSample[0], @outSample[0]);

		if LEDStatus then
			LossyIntegratorLED(@FilterLEDC, @FilterLED, @outSample[0], @outSample[0]);

		if FilterHighPass then
			LossyIntegratorHighPass(@FilterHi, @outSample[0], @outSample[0]);

		// negative because signal phase is flipped on A500/A1200 for some reason
		outSample[0] := outSample[0] * Amp;
		outSample[1] := outSample[1] * Amp;

		{if PreventClipping then
		begin}
			sndOut[j*2]   := CLAMP2(Trunc(outSample[0]), -32768, 32767, ClippedSamples);
			sndOut[j*2+1] := CLAMP2(Trunc(outSample[1]), -32768, 32767, ClippedSamples);
		{end
		else
		begin
			sndOut[j*2]   := Trunc(outSample[0]);
			sndOut[j*2+1] := Trunc(outSample[1]);
		end;}
	end;
end;

// Renders full or partial pattern to floating point sample buffer
//
function TPTModule.RenderPatternFloat(var FloatBuf: TFloatArray;
	Rows: Byte; Mono, Normalize, BoostHighs: Boolean): Cardinal;
const
	divider = 1.0 / 32768.0;
var
	Buf: TArray<SmallInt>;
	i: Integer;
begin
	if RenderPattern(Buf, Rows, Mono, Normalize, BoostHighs) < 1 then Exit(0);

	Result := Length(Buf);

	if Mono then
	begin
		SetLength(FloatBuf, Result div 2);
		for i := 0 to Result div 2-1 do
			FloatBuf[i] := ((Buf[i*2] + Buf[i*2+1]) / 2) * divider
	end
	else
	begin
		SetLength(FloatBuf, Result);
		for i := 0 to Result-1 do
			FloatBuf[i] := Buf[i];
	end;
end;

function TPTModule.RenderPattern(var Buf: TArray<SmallInt>;
	Rows: Byte; Mono, Normalize, BoostHighs: Boolean): Cardinal;
var
	Stream: TMemoryStream;
	OrigPatt, OrigOrderCount: Byte;
//	OrigPlayFreq, SampleRate: Cardinal;
//	Sam: TSample;
//	i: Integer;

begin
	Stop;
	Mixing := False;
	DisableMixer := True;

	RenderMode := RENDER_SAMPLE;
	RenderInfo.SamplesRendered := 0;
	RenderInfo.LastRow := Rows;

	{OrigPlayFreq := outputFreq;
	SetOutputFreq(SampleRate);}
	OrigOrderCount := Info.OrderCount;
	Info.OrderCount := 1;
	OrigPatt := OrderList[0];
	OrderList[0] := MAX_PATTERNS;

	PlayPos.Pattern := OrderList[0];
	PlayPos.Row := 0;
	PlayPos.Order := 0;
	PlayMode := PLAY_PATTERN;

	InitPlay(OrderList[0]);

	Stream := TMemoryStream.Create;

	while PlayMode = PLAY_PATTERN do
	begin
		IntMusic;

		MixSampleBlock(MixBuffer, samplesPerFrame);
		Stream.WriteBuffer(MixBuffer[0], samplesPerFrame*4);

		Inc(RenderInfo.SamplesRendered, samplesPerFrame);
	end;

	//Result := RenderInfo.SamplesRendered;
	RenderMode := RENDER_NONE;
	Stop;
	OrderList[0] := OrigPatt;
	Info.OrderCount := OrigOrderCount;

	Stream.Seek(0, soFromBeginning);

	Result := Stream.Size;
	SetLength(Buf, Result div 2 + 1);
	Stream.ReadBuffer(Buf[0], Result);

	Stream.Free;
end;

// Renders full or partial pattern to a sample
//
function TPTModule.RenderToSample(DestSample: Byte; Period: Word; Rows: Byte;
	Normalize, BoostHighs: Boolean): Cardinal;
var
	Sam: TSample;
	FloatBuf: TFloatArray;
begin
	if (DestSample >= Samples.Count) then Exit(0);

	Sam := Samples[DestSample];
	with Sam do
	begin
		Volume := 64;
		Finetune := 0;
		LoopStart  := 0;
		LoopLength := 1;
	end;

	Result := RenderPatternFloat(FloatBuf, Rows, True, Normalize, BoostHighs);

	Sam.ResampleFromBuffer(FloatBuf, outputFreq, PeriodToHz(Period),
		{SOXR_VHQ}6, Normalize, BoostHighs);
end;

function TPTModule.PatternToWAV(const Filename: String; Period: Word; Rows: Byte;
	Normalize, BoostHighs: Boolean): Cardinal;
var
//	Wav: TWavWriter; !!!
	Buf: TArray<SmallInt>;
begin
	Result := 0;
{	Wav := TWavWriter.Create(Filename, outputFreq, 2, 16);
	Result := RenderPattern(Buf, Rows, True, Normalize, BoostHighs);
	Wav.WriteWordData(@Buf[0], Length(Buf));
	Wav.Free;}
end;

// Renders song to a WAV file
//   Loops = how many times to loop song
//   Tail  = length of fadeout (in seconds)
//   Result: amount of samples written
//
function TPTModule.RenderToWAV(const Filename: String; Loops: Byte = 1; Tail: Byte = 0): Cardinal;
{var
	i: Integer;
	Wav: TWavWriter;
	Len, TailedLen: Cardinal;
	Stream: TMemoryStream;
	sV, sMin, sMax: SmallInt;
	Amp, CurrAmp: Single;
label
	Done; !!! }
begin
	Result := 0;
{	Len := GetLength(Loops, True);

	Mixing := False;
	DisableMixer := True;

	RenderMode := RENDER_FILE;
	RenderInfo.SamplesRendered := 0;
	RenderInfo.LastRow := 63;

	PlayPos.Pattern := OrderList[0];
	PlayPos.Row := 0;
	PlayPos.Order := 0;
	PlayMode := PLAY_SONG;
	InitPlay(OrderList[0]);

	TailedLen := Len + (Tail * outputFreq);

	Wav := nil;
	Stream := TMemoryStream.Create;
	sMin := 0; sMax := 0;

	if Assigned(OnProgressInit) then
		OnProgressInit(TailedLen, 'Rendering module...');

	while (not RenderInfo.Canceled) and (RenderInfo.SamplesRendered <= TailedLen) do
	begin
		IntMusic;

		MixSampleBlock(MixBuffer, samplesPerFrame);

		// find loudest sample
		for i := 0 to samplesPerFrame * 2 - 1 do
		begin
			sV := MixBuffer[i];
			if sV < sMin then
				sMin := sV
			else
			if sV > sMax then
				sMax := sV;
		end;

		Stream.WriteBuffer(MixBuffer[0], samplesPerFrame*4);

		Inc(RenderInfo.SamplesRendered, samplesPerFrame);
		if Assigned(OnProgress) then
			OnProgress(RenderInfo.SamplesRendered);
	end;

	if RenderInfo.Canceled then
		goto Done;

	// normalization + fadeout
	//
	if Assigned(OnProgressInit) then
		OnProgressInit(TailedLen, 'Normalizing audio...');

	Amp := 32767 / Max(sMax, Abs(sMin));
	CurrAmp := Amp;

	Stream.Seek(0, soFromBeginning);
	RenderInfo.SamplesRendered := 0;

	Wav := TWavWriter.Create(Filename, outputFreq, 2, 16);

	while (not RenderInfo.Canceled) and (RenderInfo.SamplesRendered <= TailedLen) do
	begin
		Stream.ReadBuffer(MixBuffer[0], samplesPerFrame*4);

		// normalize
		for i := 0 to samplesPerFrame * 2 - 1 do
		begin
			MixBuffer[i] := Trunc(MixBuffer[i] * CurrAmp);
			if (Tail > 0) and (i mod 2 = 0) and
				(RenderInfo.SamplesRendered >= Len) then
					CurrAmp := (1.0 - (((RenderInfo.SamplesRendered +
						(i shr 1)) - Len) / (TailedLen - Len))) * Amp;
		end;

		// write to file
		Wav.WriteWordData(@MixBuffer[0], samplesPerFrame * 2);

		Inc(RenderInfo.SamplesRendered, samplesPerFrame);
		if Assigned(OnProgress) then
			OnProgress(RenderInfo.SamplesRendered);
	end;

Done:

	RenderMode := RENDER_NONE;
	Stop;

	if Wav <> nil then
		Wav.Free;
	Stream.Free;

	if RenderInfo.Canceled then
	begin
		Result := 0;
		Log('Rendering canceled by user.');
	end
	else
	begin
		Result := TailedLen;
		Log('Rendered module to %s.', [Filename]);
	end;}
end;

function TPTModule.GetLength(Loops: Byte = 0; InSamples: Boolean = False): Cardinal;
begin
	Stop;
	Mixing := False;
	DisableMixer := True;

	RenderMode := RENDER_LENGTH;
	RenderInfo.SamplesRendered := 0;

	PlayPos.Pattern := OrderList[0];
	PlayPos.Row := 0;
	PlayPos.Order := 0;
	PlayMode := PLAY_SONG;
	InitPlay(OrderList[0]);

	RenderInfo.LoopsWanted := Loops;

	while PlayMode = PLAY_SONG do
	begin
		IntMusic;
		Inc(RenderInfo.SamplesRendered, samplesPerFrame);
	end;

	if InSamples then
		Result := RenderInfo.SamplesRendered
	else
		Result := RenderInfo.SamplesRendered div outputFreq;

	RenderMode := RENDER_NONE;
	Stop;

	{Log('OrderChanges=%d  Order=%d  Pattern=%d', [renderinfo.OrderChanges, playpos.Order, playpos.Pattern]);
	Log('SamplesRendered=%d  Result=%d', [renderinfo.SamplesRendered, Result]);
	Log('');}
end;


end.



