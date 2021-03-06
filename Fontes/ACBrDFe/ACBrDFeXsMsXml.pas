{******************************************************************************}
{ Projeto: Componente ACBrNFe                                                  }
{  Biblioteca multiplataforma de componentes Delphi para emiss�o de Nota Fiscal}
{ eletr�nica - NFe - http://www.nfe.fazenda.gov.br                             }

{ Direitos Autorais Reservados (c) 2015 Daniel Simoes de Almeida               }
{                                       Andr� Ferreira de Moraes               }

{ Colaboradores nesse arquivo:                                                 }

{  Voc� pode obter a �ltima vers�o desse arquivo na pagina do Projeto ACBr     }
{ Componentes localizado em http://www.sourceforge.net/projects/acbr           }


{  Esta biblioteca � software livre; voc� pode redistribu�-la e/ou modific�-la }
{ sob os termos da Licen�a P�blica Geral Menor do GNU conforme publicada pela  }
{ Free Software Foundation; tanto a vers�o 2.1 da Licen�a, ou (a seu crit�rio) }
{ qualquer vers�o posterior.                                                   }

{  Esta biblioteca � distribu�da na expectativa de que seja �til, por�m, SEM   }
{ NENHUMA GARANTIA; nem mesmo a garantia impl�cita de COMERCIABILIDADE OU      }
{ ADEQUA��O A UMA FINALIDADE ESPEC�FICA. Consulte a Licen�a P�blica Geral Menor}
{ do GNU para mais detalhes. (Arquivo LICEN�A.TXT ou LICENSE.TXT)              }

{  Voc� deve ter recebido uma c�pia da Licen�a P�blica Geral Menor do GNU junto}
{ com esta biblioteca; se n�o, escreva para a Free Software Foundation, Inc.,  }
{ no endere�o 59 Temple Street, Suite 330, Boston, MA 02111-1307 USA.          }
{ Voc� tamb�m pode obter uma copia da licen�a em:                              }
{ http://www.opensource.org/licenses/lgpl-license.php                          }

{ Daniel Sim�es de Almeida  -  daniel@djsystem.com.br  -  www.djsystem.com.br  }
{              Pra�a Anita Costa, 34 - Tatu� - SP - 18270-410                  }

{******************************************************************************}

{$I ACBr.inc}

unit ACBrDFeXsMsXml;

interface

uses
  Classes, SysUtils,
  ACBrDFeSSL,
  ACBrMSXML2_TLB,
  Windows, ActiveX, ComObj;

type

  { TDFeSSLXmlSignMsXml }

  TDFeSSLXmlSignMsXml = class( TDFeSSLXmlSignClass )
   private
   protected
     procedure VerificarValoresPadrao(var SignatureNode: String;
       var SelectionNamespaces: String);
   public
     function Assinar(const ConteudoXML, docElement, infElement: String;
       SignatureNode: String = ''; SelectionNamespaces: String = '';
       IdSignature: String = ''): String; override;
     function Validar(const ConteudoXML, ArqSchema: String;
       out MsgErro: String): Boolean; override;
     function VerificarAssinatura(const ConteudoXML: String; out MsgErro: String;
       const infElement: String; SignatureNode: String = '';
       SelectionNamespaces: String = ''): Boolean; override;
   end;

implementation

uses
  strutils,
  ACBrUtil, ACBrDFeUtil, ACBrDFeException,
  ACBr_WinCrypt{, ACBrDFeWinCrypt};

{ TDFeSSLXmlSignMsXml }

procedure TDFeSSLXmlSignMsXml.VerificarValoresPadrao(var SignatureNode: String;
  var SelectionNamespaces: String);
begin
  if SignatureNode = '' then
    SignatureNode := CSIGNATURE_NODE;

  if SelectionNamespaces = '' then
    SelectionNamespaces := CDSIGNS
  else
  begin
    if LeftStr(SelectionNamespaces, Length(CDSIGNS)) <> CDSIGNS then
      SelectionNamespaces := CDSIGNS + ' ' + SelectionNamespaces;
  end;
end;

function TDFeSSLXmlSignMsXml.Assinar(const ConteudoXML, docElement,
  infElement: String; SignatureNode: String; SelectionNamespaces: String;
  IdSignature: String): String;
var
  AXml, XmlAss: AnsiString;
  xmldoc: IXMLDOMDocument3;
  xmldsig: IXMLDigitalSignatureEx;
  dsigKey: IXMLDSigKeyEx;
  signedKey: IXMLDSigKey;
begin
  Result := '';
  if (CoInitialize(nil) = E_FAIL) then
    raise EACBrDFeException.Create('Erro ao inicializar biblioteca COM');

  try
    FpDFeSSL.CarregarCertificadoSeNecessario;

    // IXMLDOMDocument3 deve usar a String Nativa da IDE //
    {$IfDef FPC2}
     AXml := ACBrUTF8ToAnsi(ConteudoXML);
    {$Else}
     AXml := UTF8ToNativeString(ConteudoXML);
    {$EndIf}
    XmlAss := '';

    // Usa valores default, se n�o foram informados //
    VerificarValoresPadrao(SignatureNode, SelectionNamespaces);

    // Inserindo Template da Assinatura digital //
    if (not XmlEstaAssinado(AXml)) or (SignatureNode <> CSIGNATURE_NODE) then
      AXml := AdicionarSignatureElement(AXml, False, docElement, IdSignature);

    try
      // Criando XMLDOC //
      xmldoc := CoDOMDocument50.Create;
      xmldoc.async := False;
      xmldoc.validateOnParse := False;
      xmldoc.preserveWhiteSpace := True;

      // Carregando o AXml em XMLDOC
      if (not xmldoc.loadXML( WideString(AXml) )) then
        raise EACBrDFeException.Create('N�o foi poss�vel carregar XML'+sLineBreak+ AXml);

      xmldoc.setProperty('SelectionNamespaces', SelectionNamespaces);

      //DEBUG
      //xmldoc.save('c:\temp\xmldoc.xml');

      // Criando Elemento de assinatura //
      xmldsig := CreateComObject(CLASS_MXDigitalSignature50) as IXMLDigitalSignatureEx;
      if (xmldsig = nil) then
        raise EACBrDFeException.Create('Erro ao criar Elemento para Assinatura');

      // Lendo elemento de Assinatura de XMLDOC //
      xmldsig.signature := xmldoc.selectSingleNode( WideString(SignatureNode) );
      if (xmldsig.signature = nil) then
        raise EACBrDFeException.Create('Erro ao encontrar n� para Assinatura');

      dsigKey := Nil;
      xmldsig.setStoreHandle( PCCERT_CONTEXT(FpDFeSSL.CertContextWinApi)^.hCertStore );
      xmldsig.createKeyFromCertContext( FpDFeSSL.CertContextWinApi, dsigKey);

      {GetProviderInfo( PCCERT_CONTEXT(FpDFeSSL.CertContextWinApi),
                       ProviderType,
                       ProviderName,
                       ContainerName);
      dsigKey := xmldsig.createKeyFromCSP( ProviderType,
                                           WideString(ProviderName),
                                           WideString(ContainerName), 0);}
      if (dsigKey = nil) then
        raise EACBrDFeException.Create('Falha ao obter a Chave Privada do Certificado para Assinatura.');

      // Assinando com MSXML e CryptoLib //
      signedKey := xmldsig.sign(dsigKey, CERTIFICATES);
      if (signedKey = nil) then
        raise EACBrDFeException.Create('Assinatura Falhou.');

      //DEBUG
      //xmldoc.save('c:\temp\ass.xml');
      XmlAss := AnsiString(xmldoc.xml);

      // Convertendo novamente para UTF8
      {$IfDef FPC2}
       XmlAss := ACBrAnsiToUTF8( XmlAss );
      {$Else}
       XmlAss := NativeStringToUTF8( String(XmlAss) );
      {$EndIf}

      // Ajustando o XML... CAPICOM insere um cabe�alho inv�lido
      XmlAss := AjustarXMLAssinado(XmlAss, FpDFeSSL.DadosCertificado.DERBase64);
    finally
      xmldoc := nil;
      //xmldsig := nil;
      //signedKey := nil;
      //dsigKey := nil;
    end;

    Result := XmlAss;
  finally
    CoUninitialize;
  end;
end;

function TDFeSSLXmlSignMsXml.Validar(const ConteudoXML, ArqSchema: String; out
  MsgErro: String): Boolean;
var
  DOMDocument: IXMLDOMDocument2;
  ParseError: IXMLDOMParseError;
  Schema: XMLSchemaCache50;
  AXml: String;
begin
  Result := False;
  if (CoInitialize(nil) = E_FAIL) then
    raise EACBrDFeException.Create('Erro ao inicializar biblioteca COM');

  try
    DOMDocument := CoDOMDocument50.Create;
    Schema := CoXMLSchemaCache50.Create;
    try
      DOMDocument.async := False;
      DOMDocument.resolveExternals := False;
      DOMDocument.validateOnParse := True;

      // Carregando ConteudoXML em XMLDOC. Nota: IXMLDOMDocument2 deve usar a String Nativa da IDE //
      {$IfDef FPC2}
       AXml := ACBrUTF8ToAnsi(ConteudoXML);
      {$Else}
       AXml := UTF8ToNativeString(ConteudoXML);
      {$EndIf}

      if (not DOMDocument.loadXML(WideString(AXml))) then
      begin
        ParseError := DOMDocument.parseError;
        MsgErro := ACBrStr('N�o foi poss�vel carregar o arquivo.')+sLineBreak+
                   'Err: '+IntToStr(ParseError.errorCode) + ', ' +
                   'Lin: '+IntToStr(ParseError.line) + ', ' +
                   'Pos: '+IntToStr(ParseError.linepos) + ' - ' +
                   String(ParseError.reason);
        exit;
      end;

      Schema.add(WideString(FpDFeSSL.NameSpaceURI), ArqSchema);

      DOMDocument.schemas := Schema;
      ParseError := DOMDocument.validate;

      Result := (ParseError.errorCode = 0);
      MsgErro := String(ParseError.reason);
    finally
      ParseError := nil;
      DOMDocument := nil;
      Schema := nil;
    end;
  finally
    CoUninitialize;
  end;
end;

function TDFeSSLXmlSignMsXml.VerificarAssinatura(const ConteudoXML: String; out
  MsgErro: String; const infElement: String; SignatureNode: String;
  SelectionNamespaces: String): Boolean;
var
  xmldoc: IXMLDOMDocument3;
  xmldsig: IXMLDigitalSignature;
  certNode: IXMLDOMNode;
  pKey, pKeyOut: IXMLDSigKey;
  AXml: String;
begin
  // Usa valores default, se n�o foram informados //
  VerificarValoresPadrao(SignatureNode, SelectionNamespaces);
  Result := False;
  if (CoInitialize(nil) = E_FAIL) then
    raise EACBrDFeException.Create('Erro ao inicializar biblioteca COM');

  try
    xmldoc := CoDOMDocument50.Create;
    xmldsig := CoMXDigitalSignature50.Create;
    try
      xmldoc.async := False;
      xmldoc.validateOnParse := False;
      xmldoc.preserveWhiteSpace := True;

      // Carregando ConteudoXML em XMLDOC. Nota: IXMLDOMDocument2 deve usar a String Nativa da IDE //
      {$IfDef FPC2}
       AXml := ACBrUTF8ToAnsi(ConteudoXML);
      {$Else}
       AXml := UTF8ToNativeString(ConteudoXML);
      {$EndIf}

      if (not xmldoc.loadXML(WideString(AXml))) then
      begin
        MsgErro := 'N�o foi poss�vel carregar o arquivo.';
        exit;
      end;

      xmldoc.setProperty('SelectionNamespaces', SelectionNamespaces);
      xmldsig.signature := xmldoc.selectSingleNode( WideString(SignatureNode));
      if (xmldsig.signature = nil) then
      begin
        MsgErro := 'N�o foi poss�vel ler o n� de Assinatura ('+SignatureNode+')';
        exit;
      end;

      certNode := xmldsig.signature.selectSingleNode( WideString('.//ds:KeyInfo/ds:X509Data/ds:X509Certificate'));
      if (certNode = nil) then
      begin
        MsgErro := 'Erro ao ler <X509Data> da Assinatura';
        exit;
      end;

      pKey := xmldsig.createKeyFromNode(certNode);
      if (pKey = nil) then
      begin
        MsgErro := 'Erro obter a Chave Publica de <X509Certificate>';
        exit;
      end;

      try
        pKeyOut := xmldsig.verify(pKey);
      except
        on E: Exception do
          MsgErro := 'Erro ao verificar assinatura do arquivo: ' + E.Message;
      end;
    finally
      MsgErro := ACBrStr(MsgErro);
      Result := (pKeyOut <> nil);

      pKeyOut := nil;
      pKey := nil;
      certNode := nil;
      xmldsig := nil;
      xmldoc := nil;
    end;
  finally
    CoUninitialize;
  end;
end;

end.

