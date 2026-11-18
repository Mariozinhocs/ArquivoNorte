<#
.SYNOPSIS
    ArquivoNorte - Squad A-Team
    Busca inteligente de arquivos na sua rede.

.DESCRIPTION
    Permite apontamento dinamico de diretorios locais e de rede, com atalhos de 1 clique
    100% personalizaveis, ordenacao de colunas interativa no estilo Windows Explorer
    (clique no cabecalho para alternar A-Z / Z-A / Data / Tamanho com setas indicadoras),
    autenticacao e licenciamento Node-Lock (vinculado a maquina por HMAC-SHA256),
    interface grafica moderna (WPF Dark Mode) de alto contraste e suporte a CLI.

.PARAMETER TermoBusca
    Termo ou palavra-chave para filtrar o nome do arquivo.

.PARAMETER Diretorio
    Diretorio ou lista de diretorios (separados por ponto e virgula) onde a busca deve ser feita.

.PARAMETER Extensao
    Filtro de extensao (ex: docx, pdf, xlsx, *).

.PARAMETER NoGui
    Forca a execucao no modo console/terminal.
#>

param(
    [Parameter(Mandatory=$false, Position=0)]
    [string]$TermoBusca = "",

    [Parameter(Mandatory=$false)]
    [string]$Diretorio = "",

    [Parameter(Mandatory=$false)]
    [string]$Extensao = "*",

    [switch]$NoGui
)

# Caminho do diretorio do aplicativo
$scriptDir = if (![string]::IsNullOrEmpty($PSScriptRoot)) { 
    $PSScriptRoot 
} elseif ($MyInvocation.MyCommand.Path) { 
    Split-Path -Parent $MyInvocation.MyCommand.Path 
} elseif (![string]::IsNullOrEmpty([System.AppDomain]::CurrentDomain.BaseDirectory)) {
    [System.AppDomain]::CurrentDomain.BaseDirectory.TrimEnd('\')
} else { 
    (Get-Location).Path 
}

# ==============================================================================
# CAMADA DE SEGURANCA: LICENCIAMENTO E AUTENTICACAO NODE-LOCK
# ==============================================================================
$SecretSalt = "ArquivoNorte.A-Team.SecureHMAC.2026.MarioHenrique"

function Get-MachineFingerprint {
    try {
        $uuid = (Get-CimInstance Win32_ComputerSystemProduct -ErrorAction Stop).UUID
        if ([string]::IsNullOrWhiteSpace($uuid)) {
            $uuid = (Get-CimInstance Win32_BaseBoard).SerialNumber
        }
    } catch {
        $uuid = $env:COMPUTERNAME
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($uuid)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash($bytes)
    $hex = [System.BitConverter]::ToString($hash).Replace("-", "")
    return "AN-" + $hex.Substring(0, 4) + "-" + $hex.Substring(4, 4) + "-" + $hex.Substring(8, 4) + "-" + $hex.Substring(12, 4)
}

function Test-LicenseKey([string]$key) {
    if ([string]::IsNullOrWhiteSpace($key)) { return $null }
    $cleanKey = $key.Trim().ToUpper()
    $parts = $cleanKey.Split('-')
    if ($parts.Count -ne 4 -or $parts[0] -ne "KEY" -or $parts[1].Length -ne 8) {
        return $null
    }

    $expDateStr = $parts[1]
    $keySig = $parts[2] + $parts[3]
    $machineID = Get-MachineFingerprint

    $payload = $machineID + "|" + $expDateStr
    $hmac = [System.Security.Cryptography.HMACSHA256]::new([System.Text.Encoding]::UTF8.GetBytes($SecretSalt))
    $hashBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($payload))
    $expectedSig = [System.BitConverter]::ToString($hashBytes).Replace("-", "").Substring(0, 8)

    if ($keySig -ne $expectedSig) {
        return [PSCustomObject]@{ IsValid = $false; IsExpired = $false }
    }

    $targetDate = [DateTime]::ParseExact($expDateStr, "yyyyMMdd", $null)
    $isExpired = ((Get-Date) -gt $targetDate)

    return [PSCustomObject]@{
        IsValid        = $true
        IsExpired      = $isExpired
        ExpirationDate = $targetDate
        ExpirationStr  = $targetDate.ToString("dd/MM/yyyy")
        Key            = $cleanKey
    }
}

function Get-SavedLicenseKey {
    $appData = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)
    $licFileUser = Join-Path (Join-Path $appData "ArquivoNorte") "licenca.lic"
    $licFileDir  = Join-Path $scriptDir "licenca_arquivonorte.lic"

    $key = $null
    if (Test-Path $licFileUser) {
        $key = [System.IO.File]::ReadAllText($licFileUser, [System.Text.Encoding]::UTF8)
    } elseif (Test-Path $licFileDir) {
        $key = [System.IO.File]::ReadAllText($licFileDir, [System.Text.Encoding]::UTF8)
    }

    if ($key) {
        return (Test-LicenseKey $key)
    }
    return $null
}

function Save-ActiveLicenseKey([string]$key) {
    $appData = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)
    $targetDir = Join-Path $appData "ArquivoNorte"
    if (!(Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
    $licFileUser = Join-Path $targetDir "licenca.lic"
    [System.IO.File]::WriteAllText($licFileUser, $key.Trim().ToUpper(), [System.Text.Encoding]::UTF8)
}

# ==============================================================================
# CONFIGURACAO DE ATALHOS RAPIDOS
# ==============================================================================
$configFile = Join-Path $scriptDir "atalhos_ccc.json"

$defaultShortcuts = @(
    [PSCustomObject]@{ Nome = "CCC 2026"; Caminho = "H:\#Assessoria CCC 2026" },
    [PSCustomObject]@{ Nome = "CCC 2025"; Caminho = "H:\Assessoria CCC - 2025" },
    [PSCustomObject]@{ Nome = "Ambos CCC"; Caminho = "H:\#Assessoria CCC 2026; H:\Assessoria CCC - 2025" },
    [PSCustomObject]@{ Nome = "Pasta Atual"; Caminho = "." }
)

function Get-AtalhosCCC {
    if (Test-Path $configFile) {
        try {
            $json = [System.IO.File]::ReadAllText($configFile, [System.Text.Encoding]::UTF8)
            $data = $json | ConvertFrom-Json
            if ($data -ne $null) {
                return @($data)
            }
            return $defaultShortcuts
        } catch {
            return $defaultShortcuts
        }
    } else {
        Save-AtalhosCCC $defaultShortcuts
        return $defaultShortcuts
    }
}

function Save-AtalhosCCC($lista) {
    try {
        $json = $lista | ConvertTo-Json -Depth 4
        [System.IO.File]::WriteAllText($configFile, $json, [System.Text.Encoding]::UTF8)
    } catch {
        Write-Warning "Falha ao salvar atalhos_ccc.json: $_"
    }
}

# ==============================================================================
# MODO CONSOLE (CLI) - Quando chamado com parametros de terminal ou flag -NoGui
# ==============================================================================
if (![string]::IsNullOrWhiteSpace($TermoBusca) -or $NoGui) {
    # Validacao de licenca em modo CLI
    $cliLic = Get-SavedLicenseKey
    if ($cliLic -eq $null -or !$cliLic.IsValid -or $cliLic.IsExpired) {
        Write-Host "==========================================================" -ForegroundColor Red
        Write-Host " [ArquivoNorte] ERRO: Maquina nao autorizada ou licenca expirada." -ForegroundColor Yellow
        Write-Host " ID desta maquina: $(Get-MachineFingerprint)" -ForegroundColor Cyan
        Write-Host " Entre em contato com o gestor (Mario Henrique) para liberacao." -ForegroundColor Gray
        Write-Host "==========================================================" -ForegroundColor Red
        exit 1
    }

    if ([string]::IsNullOrWhiteSpace($Diretorio)) {
        $Diretorios = @(
            "H:\#Assessoria CCC 2026",
            "H:\Assessoria CCC - 2025"
        )
    } else {
        $Diretorios = $Diretorio -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    }

    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host " [ArquivoNorte] Busca inteligente de arquivos na sua rede" -ForegroundColor Yellow
    Write-Host " Licenca ativa ate: $($cliLic.ExpirationStr)" -ForegroundColor DarkGreen
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "Buscando por '$TermoBusca' (Extensao: $Extensao)..." -ForegroundColor Gray
    Write-Host "Diretorios: $($Diretorios -join ' | ')" -ForegroundColor DarkCyan
    Write-Host ""

    $resultadosEncontrados = 0

    foreach ($dir in $Diretorios) {
        if (Test-Path $dir) {
            $resultados = Get-ChildItem -Path $dir -Filter "*$TermoBusca*.$Extensao" -Recurse -ErrorAction SilentlyContinue | Where-Object { !($_.PSIsContainer) }
            
            if ($resultados) {
                foreach ($arquivo in $resultados) {
                    $resultadosEncontrados++
                    Write-Host "[$($arquivo.LastWriteTime.ToString('dd/MM/yyyy HH:mm'))] " -NoNewline -ForegroundColor DarkGray
                    Write-Host $arquivo.Name -ForegroundColor Green
                    Write-Host "   Pasta: " -NoNewline -ForegroundColor DarkGray
                    Write-Host $arquivo.DirectoryName -ForegroundColor DarkCyan
                    Write-Host ""
                }
            }
        } else {
            Write-Host "[Aviso] Diretorio nao acessivel: $dir" -ForegroundColor Red
        }
    }

    Write-Host "==========================================================" -ForegroundColor Cyan
    if ($resultadosEncontrados -gt 0) {
        Write-Host " Concluido! $resultadosEncontrados arquivo(s) encontrado(s)." -ForegroundColor Yellow
    } else {
        Write-Host " Nenhum arquivo encontrado com o termo '$TermoBusca'." -ForegroundColor Red
    }
    Write-Host "==========================================================" -ForegroundColor Cyan
    exit
}

# ==============================================================================
# MODO INTERFACE GRAFICA (GUI WPF) - Execucao interativa padrao
# ==============================================================================

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# Desvincula o processo do grupo padrao do PowerShell na barra de tarefas do Windows
try {
    $sigAppId = @'
[DllImport("shell32.dll", SetLastError = true)]
public static extern void SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string AppID);
'@
    Add-Type -MemberDefinition $sigAppId -Name "TaskbarNative" -Namespace "ArquivoNorte" -ErrorAction SilentlyContinue
    [ArquivoNorte.TaskbarNative]::SetCurrentProcessExplicitAppUserModelID("ArquivoNorte.App.v2")
} catch { }

# ==============================================================================
# JANELA DE ATIVACAO DE LICENCA (SE NECESSARIO)
# ==============================================================================
function Show-ActivationDialog([string]$mensagemAviso = "") {
    [xml]$actXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Ativação de Licença - ArquivoNorte"
        Height="470" Width="540"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        Background="#121316" Foreground="#F4F4F5"
        FontFamily="Segoe UI">
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="*" />
            <RowDefinition Height="Auto" />
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Background="#1B1D22" BorderBrush="#2C2F36" BorderThickness="1" CornerRadius="8" Padding="14,10" Margin="0,0,0,14">
            <StackPanel>
                <TextBlock Text="🔒 Ativação de Licença Corporativa" FontSize="16" FontWeight="Bold" Foreground="#38BDF8" />
                <TextBlock Text="ArquivoNorte - Busca inteligente de arquivos na sua rede" FontSize="11" Foreground="#94A3B8" Margin="0,2,0,0" />
            </StackPanel>
        </Border>

        <Border Grid.Row="1" Background="#1B1D22" BorderBrush="#2C2F36" BorderThickness="1" CornerRadius="8" Padding="14" Margin="0,0,0,14">
            <StackPanel>
                <TextBlock Name="txtNotice" Text="Esta máquina precisa de uma licença de uso válida." FontSize="12" Foreground="#E2E8F0" Margin="0,0,0,10" TextWrapping="Wrap" />
                <TextBlock Text="IDENTIFICADOR DESTA MÁQUINA:" FontSize="11" FontWeight="Bold" Foreground="#06B6D4" Margin="0,0,0,4" />
                <Grid Margin="0,0,0,8">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*" />
                        <ColumnDefinition Width="Auto" />
                    </Grid.ColumnDefinitions>
                    <TextBox Name="txtMachineID" IsReadOnly="True" Background="#0F1013" Foreground="#38BDF8" BorderBrush="#334155" FontWeight="Bold" FontSize="13" Padding="8,6" VerticalContentAlignment="Center" />
                    <Button Name="btnCopyID" Grid.Column="1" Margin="8,0,0,0" Padding="14,6" Background="#272A30" Foreground="#E2E8F0" BorderBrush="#3F444E" Content="📋 Copiar ID" Cursor="Hand" />
                </Grid>
                <TextBlock Text="💡 Envie o código acima ao gestor (Mario Henrique) para liberação." FontSize="11" Foreground="#64748B" TextWrapping="Wrap" />
            </StackPanel>
        </Border>

        <Border Grid.Row="2" Background="#1B1D22" BorderBrush="#2C2F36" BorderThickness="1" CornerRadius="8" Padding="14" Margin="0,0,0,14">
            <StackPanel>
                <TextBlock Text="INSIRA SUA CHAVE DE ATIVAÇÃO:" FontSize="11" FontWeight="Bold" Foreground="#06B6D4" Margin="0,0,0,4" />
                <TextBox Name="txtKey" Background="#0F1013" Foreground="#F8FAFC" BorderBrush="#334155" FontSize="13" Padding="8,6" VerticalContentAlignment="Center" Margin="0,0,0,8" />
                <TextBlock Name="txtActStatus" Text="" FontSize="11" FontWeight="SemiBold" Foreground="#EF4444" TextWrapping="Wrap" />
            </StackPanel>
        </Border>

        <DockPanel Grid.Row="3" LastChildFill="False">
            <Button Name="btnCancel" DockPanel.Dock="Left" Padding="14,7" Background="#272A30" Foreground="#94A3B8" BorderBrush="#3F444E" Content="Sair" Cursor="Hand" />
            <Button Name="btnActivate" DockPanel.Dock="Right" Padding="20,7" Background="#0284C7" Foreground="White" FontWeight="Bold" BorderThickness="0" Content="🚀 Ativar Aplicação" Cursor="Hand" />
        </DockPanel>
    </Grid>
</Window>
'@

    $actReader = (New-Object System.Xml.XmlNodeReader $actXaml)
    $actWindow = [Windows.Markup.XamlReader]::Load($actReader)

    # Aplica icone na janela de ativacao
    $iconPathLocal = Join-Path $scriptDir "icon_ArquivoNorte.png"
    if (Test-Path $iconPathLocal) {
        try {
            $uriIco = New-Object System.Uri($iconPathLocal, [System.UriKind]::Absolute)
            $bmpIco = New-Object System.Windows.Media.Imaging.BitmapImage
            $bmpIco.BeginInit()
            $bmpIco.UriSource = $uriIco
            $bmpIco.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bmpIco.EndInit()
            $actWindow.Icon = $bmpIco
        } catch {}
    }

    $txtNotice     = $actWindow.FindName("txtNotice")
    $txtMachineID  = $actWindow.FindName("txtMachineID")
    $btnCopyID     = $actWindow.FindName("btnCopyID")
    $txtKey        = $actWindow.FindName("txtKey")
    $txtActStatus  = $actWindow.FindName("txtActStatus")
    $btnCancel     = $actWindow.FindName("btnCancel")
    $btnActivate   = $actWindow.FindName("btnActivate")

    $mid = Get-MachineFingerprint
    $txtMachineID.Text = $mid

    if (![string]::IsNullOrWhiteSpace($mensagemAviso)) {
        $txtNotice.Text = $mensagemAviso
        $txtNotice.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F59E0B")
    }

    $btnCopyID.Add_Click({
        [System.Windows.Clipboard]::SetText($txtMachineID.Text)
        $btnCopyID.Content = "✅ Copiado!"
    })

    $script:ativadoComSucesso = $false

    $btnActivate.Add_Click({
        $inputKey = $txtKey.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($inputKey)) {
            $txtActStatus.Text = "Por favor, insira a chave de ativação."
            return
        }

        $res = Test-LicenseKey $inputKey
        if ($res -eq $null -or !$res.IsValid) {
            $txtActStatus.Text = "❌ Chave de ativação inválida para este computador."
            return
        }

        if ($res.IsExpired) {
            $txtActStatus.Text = "⚠️ Esta chave expirou em $($res.ExpirationStr). Solicite uma nova chave ao gestor."
            return
        }

        Save-ActiveLicenseKey $inputKey
        $script:ativadoComSucesso = $true
        [System.Windows.MessageBox]::Show("ArquivoNorte ativado com sucesso!`r`nValidade da Licença: até $($res.ExpirationStr)", "Sucesso", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        $actWindow.Close()
    })

    $btnCancel.Add_Click({
        $actWindow.Close()
    })

    $actWindow.ShowDialog() | Out-Null
    return $script:ativadoComSucesso
}

# ==============================================================================
# VERIFICACAO PREVIA DA LICENCA ANTES DE CARREGAR A JANELA PRINCIPAL
# ==============================================================================
$activeLic = Get-SavedLicenseKey

if ($activeLic -eq $null -or !$activeLic.IsValid) {
    $ok = Show-ActivationDialog "Esta máquina ainda não está licenciada para uso. Solicite a chave de ativação ao gestor."
    if (!$ok) { exit }
    $activeLic = Get-SavedLicenseKey
} elseif ($activeLic.IsExpired) {
    $ok = Show-ActivationDialog "Sua licença expirou em $($activeLic.ExpirationStr). Solicite a renovação ao gestor."
    if (!$ok) { exit }
    $activeLic = Get-SavedLicenseKey
}

if ($activeLic -eq $null -or !$activeLic.IsValid -or $activeLic.IsExpired) {
    exit
}

# ==============================================================================
# XAML DA JANELA PRINCIPAL
# ==============================================================================
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ArquivoNorte | Busca inteligente de arquivos na sua rede"
        Height="720" Width="1040"
        MinHeight="560" MinWidth="820"
        WindowStartupLocation="CenterScreen"
        Background="#121316" Foreground="#F4F4F5"
        FontFamily="Segoe UI">
    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="*" />
            <RowDefinition Height="Auto" />
        </Grid.RowDefinitions>

        <!-- CABECALHO ARQUIVONORTE -->
        <Border Grid.Row="0" Background="#1B1D22" BorderBrush="#2C2F36" BorderThickness="1" CornerRadius="8" Padding="14,10" Margin="0,0,0,12">
            <DockPanel LastChildFill="True">
                <StackPanel Orientation="Horizontal" DockPanel.Dock="Right" VerticalAlignment="Center">
                    <Border Name="brdLicenseBadge" Background="#064E3B" CornerRadius="5" Padding="8,4" Margin="0,0,8,0">
                        <TextBlock Name="txtLicenseInfo" Text="🛡️ Licença Ativa" Foreground="#A7F3D0" FontSize="11" FontWeight="SemiBold" />
                    </Border>
                    <Border Background="#0E7490" CornerRadius="5" Padding="10,4" Margin="0,0,8,0">
                        <TextBlock Text="SQUAD A-TEAM" Foreground="#ECFEFF" FontSize="11" FontWeight="Bold" />
                    </Border>
                    <Border Background="#262A33" CornerRadius="5" Padding="8,4">
                        <TextBlock Text="v2.5" Foreground="#94A3B8" FontSize="11" FontWeight="SemiBold" />
                    </Border>
                </StackPanel>
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <Border Name="brdLogo" Background="White" CornerRadius="6" Padding="8,4" Margin="0,0,14,0" VerticalAlignment="Center" Visibility="Collapsed">
                        <Image Name="imgLogo" Height="40" RenderOptions.BitmapScalingMode="HighQuality" />
                    </Border>
                    <StackPanel VerticalAlignment="Center">
                        <TextBlock Name="txtBrandTitle" Text="ArquivoNorte" FontSize="20" FontWeight="Bold" Foreground="#38BDF8" />
                        <TextBlock Text="Busca inteligente de arquivos na sua rede" FontSize="12" Foreground="#94A3B8" Margin="0,2,0,0" />
                    </StackPanel>
                </StackPanel>
            </DockPanel>
        </Border>

        <!-- SECAO 1: APONTAMENTO DE DIRETORIO E ATALHOS -->
        <Border Grid.Row="1" Background="#1B1D22" BorderBrush="#2C2F36" BorderThickness="1" CornerRadius="8" Padding="16,12" Margin="0,0,0,12">
            <StackPanel>
                <DockPanel Margin="0,0,0,6">
                    <TextBlock Text="DIRET&#211;RIO ALVO DA CONSULTA (Selecione uma pasta ou insira caminhos separados por ';')" FontSize="11" FontWeight="Bold" Foreground="#06B6D4" />
                </DockPanel>
                
                <Grid Margin="0,0,0,10">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*" />
                        <ColumnDefinition Width="Auto" />
                    </Grid.ColumnDefinitions>
                    
                    <TextBox Name="txtDirectory" Grid.Column="0"
                             Background="#0F1013" Foreground="#F8FAFC" BorderBrush="#334155" BorderThickness="1"
                             FontSize="13" Padding="10,7" VerticalContentAlignment="Center"
                             Text="H:\#Assessoria CCC 2026; H:\Assessoria CCC - 2025" />
                    
                    <Button Name="btnBrowse" Grid.Column="1" Margin="8,0,0,0" Padding="16,7"
                            Background="#0284C7" Foreground="White" FontWeight="SemiBold" BorderThickness="0"
                            Content="Procurar Pasta..." Cursor="Hand" />
                </Grid>

                <!-- BARRA DINAMICA DE ATALHOS PERSONALIZAVEIS -->
                <DockPanel LastChildFill="True">
                    <StackPanel Orientation="Horizontal" DockPanel.Dock="Right" VerticalAlignment="Center" Margin="10,0,0,0">
                        <Button Name="btnSaveCurrent" Margin="0,0,6,0" Padding="10,4"
                                Background="#1E293B" Foreground="#38BDF8" BorderBrush="#0369A1" BorderThickness="1"
                                Content="+ Salvar Atual" FontSize="11" FontWeight="SemiBold" Cursor="Hand"
                                ToolTip="Salvar a pasta indicada no campo acima como um novo atalho r&#225;pido" />
                        <Button Name="btnManageShortcuts" Padding="10,4"
                                Background="#272A30" Foreground="#F59E0B" BorderBrush="#78350F" BorderThickness="1"
                                Content="Configurar Atalhos" FontSize="11" FontWeight="SemiBold" Cursor="Hand"
                                ToolTip="Adicionar, editar ou excluir atalhos r&#225;pidos" />
                    </StackPanel>
                    
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <TextBlock Text="Atalhos r&#225;pidos:" Foreground="#64748B" FontSize="11" VerticalAlignment="Center" Margin="0,0,8,0" />
                        <WrapPanel Name="pnlShortcuts" Orientation="Horizontal" VerticalAlignment="Center" />
                    </StackPanel>
                </DockPanel>
            </StackPanel>
        </Border>

        <!-- SECAO 2: PARAMETROS DE BUSCA -->
        <Border Grid.Row="2" Background="#1B1D22" BorderBrush="#2C2F36" BorderThickness="1" CornerRadius="8" Padding="16,12" Margin="0,0,0,12">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*" />
                    <ColumnDefinition Width="200" />
                    <ColumnDefinition Width="Auto" />
                    <ColumnDefinition Width="Auto" />
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Column="0" Margin="0,0,10,0">
                    <TextBlock Text="TERMO DE BUSCA (Nome ou trecho do arquivo)" FontSize="11" FontWeight="Bold" Foreground="#06B6D4" Margin="0,0,0,6" />
                    <TextBox Name="txtSearch"
                             Background="#0F1013" Foreground="#F8FAFC" BorderBrush="#334155" BorderThickness="1"
                             FontSize="13" Padding="10,6" VerticalContentAlignment="Center" />
                </StackPanel>

                <StackPanel Grid.Column="1" Margin="0,0,10,0">
                    <TextBlock Text="TIPO / EXTENS&#195;O" FontSize="11" FontWeight="Bold" Foreground="#06B6D4" Margin="0,0,0,6" />
                    <ComboBox Name="cmbExtension"
                              Background="#0F1013" Foreground="#111827"
                              FontSize="12" Height="34" VerticalContentAlignment="Center">
                        <ComboBoxItem Content="Todos (*.*)" IsSelected="True" />
                        <ComboBoxItem Content="Word (*.docx, *.doc)" />
                        <ComboBoxItem Content="PDF (*.pdf)" />
                        <ComboBoxItem Content="Excel (*.xlsx, *.xls, *.csv)" />
                        <ComboBoxItem Content="Texto (*.txt, *.log)" />
                    </ComboBox>
                </StackPanel>

                <StackPanel Grid.Column="2" VerticalAlignment="Bottom" Margin="0,0,12,8">
                    <CheckBox Name="chkRecursive" Content="Subpastas" IsChecked="True" Foreground="#E2E8F0" FontSize="12" VerticalAlignment="Center" Cursor="Hand" />
                </StackPanel>

                <Button Name="btnSearch" Grid.Column="3" VerticalAlignment="Bottom" Height="34" Padding="22,0"
                        Background="#06B6D4" Foreground="#082F49" FontWeight="Bold" FontSize="13" BorderThickness="0"
                        Content="PESQUISAR" Cursor="Hand" />
            </Grid>
        </Border>

        <!-- SECAO 3: RESULTADOS COM ALTO CONTRASTE -->
        <Border Grid.Row="3" Background="#1B1D22" BorderBrush="#2C2F36" BorderThickness="1" CornerRadius="8" Padding="12">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto" />
                    <RowDefinition Height="*" />
                </Grid.RowDefinitions>

                <!-- STATUS E CONTAGEM -->
                <DockPanel Grid.Row="0" Margin="4,0,4,8">
                    <TextBlock Name="txtResultCount" DockPanel.Dock="Right" Text="0 arquivo(s) encontrado(s)" FontSize="12" FontWeight="Bold" Foreground="#38BDF8" />
                    <TextBlock Name="txtStatus" Text="Pronto. Aponte o diretorio e pesquise." FontSize="12" Foreground="#94A3B8" />
                </DockPanel>

                <!-- LISTAGEM COM TEMPLATE DE ALTO CONTRASTE -->
                <ListView Name="lstResults" Grid.Row="1"
                          Background="#0F1013" Foreground="#F8FAFC" BorderBrush="#2C2F36" BorderThickness="1">
                    <ListView.Resources>
                        <SolidColorBrush x:Key="{x:Static SystemColors.HighlightBrushKey}" Color="#0369A1" />
                        <SolidColorBrush x:Key="{x:Static SystemColors.HighlightTextBrushKey}" Color="#FFFFFF" />
                        <SolidColorBrush x:Key="{x:Static SystemColors.InactiveSelectionHighlightBrushKey}" Color="#1E293B" />
                        <SolidColorBrush x:Key="{x:Static SystemColors.InactiveSelectionHighlightTextBrushKey}" Color="#E2E8F0" />
                        <Style TargetType="GridViewColumnHeader">
                            <Setter Property="Background" Value="#1E2127" />
                            <Setter Property="Foreground" Value="#38BDF8" />
                            <Setter Property="FontWeight" Value="SemiBold" />
                            <Setter Property="Padding" Value="8,6" />
                            <Setter Property="BorderBrush" Value="#2C2F36" />
                            <Setter Property="BorderThickness" Value="0,0,1,1" />
                            <Setter Property="Cursor" Value="Hand" />
                            <Setter Property="ToolTip" Value="Clique para ordenar (Crescente / Decrescente)" />
                        </Style>
                    </ListView.Resources>
                    <ListView.ItemContainerStyle>
                        <Style TargetType="ListViewItem">
                            <Setter Property="Foreground" Value="#F1F5F9" />
                            <Setter Property="Background" Value="Transparent" />
                            <Setter Property="HorizontalContentAlignment" Value="Stretch" />
                            <Setter Property="VerticalContentAlignment" Value="Center" />
                            <Setter Property="Template">
                                <Setter.Value>
                                    <ControlTemplate TargetType="ListViewItem">
                                        <Border Name="Bd"
                                                Background="{TemplateBinding Background}"
                                                BorderBrush="#1E2127"
                                                BorderThickness="0,0,0,1"
                                                Padding="6,6"
                                                CornerRadius="2"
                                                SnapsToDevicePixels="true">
                                            <GridViewRowPresenter VerticalAlignment="Center" />
                                        </Border>
                                        <ControlTemplate.Triggers>
                                            <Trigger Property="IsMouseOver" Value="true">
                                                <Setter TargetName="Bd" Property="Background" Value="#1E293B" />
                                                <Setter Property="Foreground" Value="#38BDF8" />
                                            </Trigger>
                                            <Trigger Property="IsSelected" Value="true">
                                                <Setter TargetName="Bd" Property="Background" Value="#0369A1" />
                                                <Setter TargetName="Bd" Property="BorderBrush" Value="#38BDF8" />
                                                <Setter TargetName="Bd" Property="BorderThickness" Value="1" />
                                                <Setter Property="Foreground" Value="#FFFFFF" />
                                                <Setter Property="FontWeight" Value="SemiBold" />
                                            </Trigger>
                                        </ControlTemplate.Triggers>
                                    </ControlTemplate>
                                </Setter.Value>
                            </Setter>
                        </Style>
                    </ListView.ItemContainerStyle>
                    <ListView.View>
                        <GridView>
                            <GridViewColumn Header="Data de Modificacao" Width="145" DisplayMemberBinding="{Binding LastWriteTimeStr}" />
                            <GridViewColumn Header="Nome do Arquivo" Width="330" DisplayMemberBinding="{Binding Name}" />
                            <GridViewColumn Header="Tamanho" Width="95" DisplayMemberBinding="{Binding SizeStr}" />
                            <GridViewColumn Header="Pasta / Caminho" Width="410" DisplayMemberBinding="{Binding DirectoryName}" />
                        </GridView>
                    </ListView.View>
                </ListView>
            </Grid>
        </Border>

        <!-- SECAO 4: BARRA INFERIOR DE ACOES -->
        <DockPanel Grid.Row="4" Margin="0,12,0,0" LastChildFill="False">
            <TextBlock DockPanel.Dock="Left" VerticalAlignment="Center" Text="Dica: Clique nos t&#237;tulos das colunas para ordenar (Explorer). Duplo clique abre o arquivo." FontSize="11" Foreground="#64748B" />
            <StackPanel Orientation="Horizontal" DockPanel.Dock="Right">
                <Button Name="btnOpenFolder" Margin="0,0,8,0" Padding="12,7" Background="#272A30" Foreground="#E2E8F0" BorderBrush="#3F444E" BorderThickness="1" Content="Abrir Pasta no Explorer" Cursor="Hand" />
                <Button Name="btnCopyPath" Margin="0,0,8,0" Padding="12,7" Background="#272A30" Foreground="#E2E8F0" BorderBrush="#3F444E" BorderThickness="1" Content="Copiar Caminho" Cursor="Hand" />
                <Button Name="btnExport" Margin="0,0,8,0" Padding="12,7" Background="#272A30" Foreground="#38BDF8" BorderBrush="#0369A1" BorderThickness="1" Content="Exportar Relat&#243;rio" Cursor="Hand" />
                <Button Name="btnOpenFile" Padding="16,7" Background="#10B981" Foreground="#064E3B" FontWeight="Bold" BorderThickness="0" Content="Abrir Arquivo" Cursor="Hand" />
            </StackPanel>
        </DockPanel>
    </Grid>
</Window>
'@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Mapeamento de controles principais
$txtDirectory        = $window.FindName("txtDirectory")
$btnBrowse           = $window.FindName("btnBrowse")
$pnlShortcuts        = $window.FindName("pnlShortcuts")
$btnSaveCurrent      = $window.FindName("btnSaveCurrent")
$btnManageShortcuts  = $window.FindName("btnManageShortcuts")

$txtSearch           = $window.FindName("txtSearch")
$cmbExtension        = $window.FindName("cmbExtension")
$chkRecursive        = $window.FindName("chkRecursive")
$btnSearch           = $window.FindName("btnSearch")

$lstResults          = $window.FindName("lstResults")
$txtResultCount      = $window.FindName("txtResultCount")
$txtStatus           = $window.FindName("txtStatus")

$btnOpenFile         = $window.FindName("btnOpenFile")
$btnOpenFolder       = $window.FindName("btnOpenFolder")
$btnCopyPath         = $window.FindName("btnCopyPath")
$btnExport           = $window.FindName("btnExport")

$imgLogo             = $window.FindName("imgLogo")
$brdLogo             = $window.FindName("brdLogo")
$txtBrandTitle       = $window.FindName("txtBrandTitle")
$txtLicenseInfo      = $window.FindName("txtLicenseInfo")

# Exibe dados da licenca no cabecalho
if ($activeLic -ne $null) {
    $txtLicenseInfo.Text = "🛡️ Licença até " + $activeLic.ExpirationStr
    $txtLicenseInfo.ToolTip = "ID desta máquina: " + (Get-MachineFingerprint) + "`nChave ativa: " + $activeLic.Key
}

# Carregamento do Logo Oficial para o Cabecalho
$logoPath = Join-Path $scriptDir "Logo_ArquivoNorte.png"
if (Test-Path $logoPath) {
    try {
        $uriLogo = New-Object System.Uri($logoPath, [System.UriKind]::Absolute)
        $bmpLogo = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmpLogo.BeginInit()
        $bmpLogo.UriSource = $uriLogo
        $bmpLogo.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bmpLogo.EndInit()

        $imgLogo.Source = $bmpLogo
        $brdLogo.Visibility = [System.Windows.Visibility]::Visible
        $txtBrandTitle.Visibility = [System.Windows.Visibility]::Collapsed
    } catch {}
}

# Carregamento do Icone Oficial para a Barra de Tarefas e Janela
$iconPath = Join-Path $scriptDir "icon_ArquivoNorte.png"
if (Test-Path $iconPath) {
    try {
        $uriIcon = New-Object System.Uri($iconPath, [System.UriKind]::Absolute)
        $bmpIcon = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmpIcon.BeginInit()
        $bmpIcon.UriSource = $uriIcon
        $bmpIcon.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bmpIcon.EndInit()

        $window.Icon = $bmpIcon
    } catch {}
} elseif ($window.Icon -eq $null -and $bmpLogo -ne $null) {
    $window.Icon = $bmpLogo
}

# ==============================================================================
# RENDERIZACAO DINAMICA DOS ATALHOS RAPIDOS
# ==============================================================================
function Refresh-ShortcutsUI {
    $pnlShortcuts.Children.Clear()
    $atalhos = Get-AtalhosCCC

    foreach ($item in $atalhos) {
        $btn = New-Object System.Windows.Controls.Button
        $btn.Content = $item.Nome
        $btn.Margin = (New-Object System.Windows.Thickness(0, 0, 6, 0))
        $btn.Padding = (New-Object System.Windows.Thickness(10, 4, 10, 4))
        $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#272A30")
        $btn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E2E8F0")
        $btn.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3F444E")
        $btn.BorderThickness = (New-Object System.Windows.Thickness(1))
        $btn.FontSize = 11
        $btn.Cursor = [System.Windows.Input.Cursors]::Hand
        $btn.ToolTip = "Apontar para: " + $item.Caminho

        $caminhoAlvo = $item.Caminho
        $nomeAlvo = $item.Nome

        $btn.Add_Click({
            $resolved = if ($caminhoAlvo -eq ".") { (Get-Location).Path } else { $caminhoAlvo }
            $txtDirectory.Text = $resolved
            $txtStatus.Text = "Diretorio definido para [$nomeAlvo]: $resolved"
        }.GetNewClosure())

        $pnlShortcuts.Children.Add($btn) | Out-Null
    }
}

Refresh-ShortcutsUI

# ==============================================================================
# ORDENACAO INTERATIVA DE COLUNAS (ESTILO WINDOWS EXPLORER)
# ==============================================================================
$script:lastSortProperty = ""
$script:lastSortDirection = [System.ComponentModel.ListSortDirection]::Ascending

$lstResults.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler]{
    param($sender, $e)

    $header = $e.OriginalSource -as [System.Windows.Controls.GridViewColumnHeader]
    if (!$header -or !$header.Column -or $header.Role -eq [System.Windows.Controls.GridViewColumnHeaderRole]::Padding) {
        return
    }

    $col = $header.Column
    $headerText = [string]$col.Header

    $prop = ""
    $baseName = ""

    if ($headerText -like "*Data*") {
        $prop = "LastWriteTime"
        $baseName = "Data de Modificacao"
    } elseif ($headerText -like "*Nome*") {
        $prop = "Name"
        $baseName = "Nome do Arquivo"
    } elseif ($headerText -like "*Tamanho*") {
        $prop = "Length"
        $baseName = "Tamanho"
    } elseif ($headerText -like "*Pasta*" -or $headerText -like "*Caminho*") {
        $prop = "DirectoryName"
        $baseName = "Pasta / Caminho"
    } else {
        return
    }

    # Alterna direcao da ordenacao
    if ($script:lastSortProperty -eq $prop) {
        if ($script:lastSortDirection -eq [System.ComponentModel.ListSortDirection]::Ascending) {
            $script:lastSortDirection = [System.ComponentModel.ListSortDirection]::Descending
        } else {
            $script:lastSortDirection = [System.ComponentModel.ListSortDirection]::Ascending
        }
    } else {
        $script:lastSortProperty = $prop
        if ($prop -eq "LastWriteTime") {
            $script:lastSortDirection = [System.ComponentModel.ListSortDirection]::Descending
        } else {
            $script:lastSortDirection = [System.ComponentModel.ListSortDirection]::Ascending
        }
    }

    # Restaura o titulo base de todas as colunas
    $gv = $lstResults.View -as [System.Windows.Controls.GridView]
    if ($gv) {
        foreach ($c in $gv.Columns) {
            $t = [string]$c.Header
            if ($t -like "*Data*") { $c.Header = "Data de Modificacao" }
            elseif ($t -like "*Nome*") { $c.Header = "Nome do Arquivo" }
            elseif ($t -like "*Tamanho*") { $c.Header = "Tamanho" }
            elseif ($t -like "*Pasta*" -or $t -like "*Caminho*") { $c.Header = "Pasta / Caminho" }
        }
    }

    # Aplica indicador de seta
    $arrow = if ($script:lastSortDirection -eq [System.ComponentModel.ListSortDirection]::Ascending) { (" " + [char]0x25B2) } else { (" " + [char]0x25BC) }
    $col.Header = $baseName + $arrow

    # Reordena a visao de itens
    $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($lstResults.Items)
    if ($view) {
        $view.SortDescriptions.Clear()
        $view.SortDescriptions.Add([System.ComponentModel.SortDescription]::new($prop, $script:lastSortDirection))
        $view.Refresh()
    }
})

# ==============================================================================
# JANELA MODAL: GERENCIADOR DE ATALHOS
# ==============================================================================
function Open-GerenciadorAtalhos([string]$prefillPath = "") {
    [xml]$modalXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Gerenciador de Atalhos R&#225;pidos - ArquivoNorte"
        Height="500" Width="680"
        MinHeight="420" MinWidth="540"
        WindowStartupLocation="CenterOwner"
        Background="#121316" Foreground="#F4F4F5"
        FontFamily="Segoe UI">
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />
            <RowDefinition Height="*" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Background="#1B1D22" BorderBrush="#2C2F36" BorderThickness="1" CornerRadius="6" Padding="14,10" Margin="0,0,0,10">
            <DockPanel LastChildFill="True">
                <TextBlock Text="Personalizar Atalhos de 1 Clique" FontSize="15" FontWeight="Bold" Foreground="#38BDF8" VerticalAlignment="Center" />
            </DockPanel>
        </Border>

        <Border Grid.Row="1" Background="#1B1D22" BorderBrush="#2C2F36" BorderThickness="1" CornerRadius="6" Padding="8" Margin="0,0,0,10">
            <ListView Name="lstModalShortcuts" Background="#0F1013" Foreground="#F8FAFC" BorderBrush="#2C2F36" BorderThickness="1">
                <ListView.Resources>
                    <SolidColorBrush x:Key="{x:Static SystemColors.HighlightBrushKey}" Color="#0369A1" />
                    <SolidColorBrush x:Key="{x:Static SystemColors.HighlightTextBrushKey}" Color="#FFFFFF" />
                    <SolidColorBrush x:Key="{x:Static SystemColors.InactiveSelectionHighlightBrushKey}" Color="#1E293B" />
                    <SolidColorBrush x:Key="{x:Static SystemColors.InactiveSelectionHighlightTextBrushKey}" Color="#E2E8F0" />
                    <Style TargetType="GridViewColumnHeader">
                        <Setter Property="Background" Value="#1E2127" />
                        <Setter Property="Foreground" Value="#38BDF8" />
                        <Setter Property="FontWeight" Value="SemiBold" />
                        <Setter Property="Padding" Value="8,6" />
                        <Setter Property="BorderBrush" Value="#2C2F36" />
                        <Setter Property="BorderThickness" Value="0,0,1,1" />
                    </Style>
                </ListView.Resources>
                <ListView.ItemContainerStyle>
                    <Style TargetType="ListViewItem">
                        <Setter Property="Foreground" Value="#F1F5F9" />
                        <Setter Property="Background" Value="Transparent" />
                        <Setter Property="HorizontalContentAlignment" Value="Stretch" />
                        <Setter Property="VerticalContentAlignment" Value="Center" />
                        <Setter Property="Template">
                            <Setter.Value>
                                <ControlTemplate TargetType="ListViewItem">
                                    <Border Name="BrdModal"
                                            Background="{TemplateBinding Background}"
                                            BorderBrush="#1E2127"
                                            BorderThickness="0,0,0,1"
                                            Padding="6,5"
                                            CornerRadius="2"
                                            SnapsToDevicePixels="true">
                                        <GridViewRowPresenter VerticalAlignment="Center" />
                                    </Border>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsMouseOver" Value="true">
                                            <Setter TargetName="BrdModal" Property="Background" Value="#1E293B" />
                                            <Setter Property="Foreground" Value="#38BDF8" />
                                        </Trigger>
                                        <Trigger Property="IsSelected" Value="true">
                                            <Setter TargetName="BrdModal" Property="Background" Value="#0369A1" />
                                            <Setter TargetName="BrdModal" Property="BorderBrush" Value="#38BDF8" />
                                            <Setter TargetName="BrdModal" Property="BorderThickness" Value="1" />
                                            <Setter Property="Foreground" Value="#FFFFFF" />
                                            <Setter Property="FontWeight" Value="SemiBold" />
                                        </Trigger>
                                    </ControlTemplate.Triggers>
                                </ControlTemplate>
                            </Setter.Value>
                        </Setter>
                    </Style>
                </ListView.ItemContainerStyle>
                <ListView.View>
                    <GridView>
                        <GridViewColumn Header="Nome do Atalho" Width="170" DisplayMemberBinding="{Binding Nome}" />
                        <GridViewColumn Header="Caminho / Diret&#243;rio" Width="430" DisplayMemberBinding="{Binding Caminho}" />
                    </GridView>
                </ListView.View>
            </ListView>
        </Border>

        <Border Grid.Row="2" Background="#1B1D22" BorderBrush="#2C2F36" BorderThickness="1" CornerRadius="6" Padding="12" Margin="0,0,0,10">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto" />
                    <RowDefinition Height="Auto" />
                </Grid.RowDefinitions>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="170" />
                    <ColumnDefinition Width="*" />
                    <ColumnDefinition Width="Auto" />
                    <ColumnDefinition Width="Auto" />
                </Grid.ColumnDefinitions>

                <TextBlock Grid.Row="0" Grid.Column="0" Text="Nome do Atalho" FontSize="11" Foreground="#06B6D4" FontWeight="SemiBold" Margin="0,0,6,4" />
                <TextBlock Grid.Row="0" Grid.Column="1" Text="Caminho do Diret&#243;rio (ou m&#250;ltiplos separados por ';')" FontSize="11" Foreground="#06B6D4" FontWeight="SemiBold" Margin="0,0,6,4" />

                <TextBox Name="txtShortcutName" Grid.Row="1" Grid.Column="0" Margin="0,0,6,0" Background="#0F1013" Foreground="#F8FAFC" BorderBrush="#334155" Padding="8,5" VerticalContentAlignment="Center" />
                <TextBox Name="txtShortcutPath" Grid.Row="1" Grid.Column="1" Margin="0,0,6,0" Background="#0F1013" Foreground="#F8FAFC" BorderBrush="#334155" Padding="8,5" VerticalContentAlignment="Center" />
                <Button Name="btnBrowseModal" Grid.Row="1" Grid.Column="2" Margin="0,0,6,0" Padding="12,5" Background="#272A30" Foreground="#E2E8F0" BorderBrush="#3F444E" Content="Procurar..." Cursor="Hand" />
                <Button Name="btnAddShortcut" Grid.Row="1" Grid.Column="3" Padding="16,5" Background="#0284C7" Foreground="White" FontWeight="Bold" BorderThickness="0" Content="Salvar" Cursor="Hand" />
            </Grid>
        </Border>

        <DockPanel Grid.Row="3" LastChildFill="False">
            <Button Name="btnDeleteShortcut" DockPanel.Dock="Left" Padding="12,6" Background="#7F1D1D" Foreground="#FECACA" BorderBrush="#991B1B" Content="Excluir Selecionado" Cursor="Hand" />
            <Button Name="btnRestoreDefaults" DockPanel.Dock="Left" Margin="8,0,0,0" Padding="12,6" Background="#272A30" Foreground="#94A3B8" BorderBrush="#3F444E" Content="Restaurar Padr&#245;es" Cursor="Hand" />
            <Button Name="btnCloseModal" DockPanel.Dock="Right" Padding="18,6" Background="#10B981" Foreground="#064E3B" FontWeight="Bold" BorderThickness="0" Content="Fechar" Cursor="Hand" />
        </DockPanel>
    </Grid>
</Window>
'@

    $modalReader = (New-Object System.Xml.XmlNodeReader $modalXaml)
    $modalWindow = [Windows.Markup.XamlReader]::Load($modalReader)
    $modalWindow.Owner = $window
    if ($window.Icon) { $modalWindow.Icon = $window.Icon }

    $lstModalShortcuts  = $modalWindow.FindName("lstModalShortcuts")
    $txtShortcutName    = $modalWindow.FindName("txtShortcutName")
    $txtShortcutPath    = $modalWindow.FindName("txtShortcutPath")
    $btnBrowseModal     = $modalWindow.FindName("btnBrowseModal")
    $btnAddShortcut     = $modalWindow.FindName("btnAddShortcut")
    $btnDeleteShortcut  = $modalWindow.FindName("btnDeleteShortcut")
    $btnRestoreDefaults = $modalWindow.FindName("btnRestoreDefaults")
    $btnCloseModal      = $modalWindow.FindName("btnCloseModal")

    if (![string]::IsNullOrWhiteSpace($prefillPath)) {
        $txtShortcutPath.Text = $prefillPath
        $txtShortcutName.Focus() | Out-Null
    }

    $RefreshModalList = {
        $lstModalShortcuts.Items.Clear()
        $lista = Get-AtalhosCCC
        foreach ($it in $lista) {
            $lstModalShortcuts.Items.Add($it) | Out-Null
        }
    }

    & $RefreshModalList

    $lstModalShortcuts.Add_SelectionChanged({
        $sel = $lstModalShortcuts.SelectedItem
        if ($sel) {
            $txtShortcutName.Text = $sel.Nome
            $txtShortcutPath.Text = $sel.Caminho
        }
    })

    $btnBrowseModal.Add_Click({
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = "Selecione o diretório para o novo atalho:"
        $dialog.ShowNewFolderButton = $false
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtShortcutPath.Text = $dialog.SelectedPath
            if ([string]::IsNullOrWhiteSpace($txtShortcutName.Text)) {
                $txtShortcutName.Text = (Split-Path -Leaf $dialog.SelectedPath)
            }
        }
    })

    $btnAddShortcut.Add_Click({
        $nome = $txtShortcutName.Text.Trim()
        $caminho = $txtShortcutPath.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($nome)) {
            [System.Windows.MessageBox]::Show("Por favor, digite um nome para o atalho.", "Nome Obrigatório", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            return
        }

        if ([string]::IsNullOrWhiteSpace($caminho)) {
            [System.Windows.MessageBox]::Show("Por favor, informe ou selecione o diretório do atalho.", "Caminho Obrigatório", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            return
        }

        $lista = @(Get-AtalhosCCC)
        $atualizado = $false
        $novaLista = @()

        foreach ($item in $lista) {
            if ($item.Nome -eq $nome) {
                $novaLista += [PSCustomObject]@{ Nome = $nome; Caminho = $caminho }
                $atualizado = $true
            } else {
                $novaLista += $item
            }
        }

        if (!$atualizado) {
            $novaLista += [PSCustomObject]@{ Nome = $nome; Caminho = $caminho }
        }

        Save-AtalhosCCC $novaLista
        & $RefreshModalList
        Refresh-ShortcutsUI

        $txtShortcutName.Text = ""
        $txtShortcutPath.Text = ""
        $txtStatus.Text = "Atalho [$nome] salvo com sucesso!"
    })

    $btnDeleteShortcut.Add_Click({
        $sel = $lstModalShortcuts.SelectedItem
        if (!$sel) {
            [System.Windows.MessageBox]::Show("Selecione um atalho na lista para excluir.", "Nenhum Atalho Selecionado", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            return
        }

        $lista = @(Get-AtalhosCCC)
        $novaLista = @($lista | Where-Object { $_.Nome -ne $sel.Nome })

        Save-AtalhosCCC $novaLista
        & $RefreshModalList
        Refresh-ShortcutsUI
        $txtShortcutName.Text = ""
        $txtShortcutPath.Text = ""
        $txtStatus.Text = "Atalho [$($sel.Nome)] removido."
    })

    $btnRestoreDefaults.Add_Click({
        $resp = [System.Windows.MessageBox]::Show("Deseja restaurar a lista padrão de atalhos?", "Confirmar Restauração", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($resp -eq [System.Windows.MessageBoxResult]::Yes) {
            Save-AtalhosCCC $defaultShortcuts
            & $RefreshModalList
            Refresh-ShortcutsUI
            $txtStatus.Text = "Atalhos padrão restaurados com sucesso."
        }
    })

    $btnCloseModal.Add_Click({
        $modalWindow.Close()
    })

    $modalWindow.ShowDialog() | Out-Null
}

# ==============================================================================
# ACOES DA BARRA DE DIRETORIO PRINCIPAL
# ==============================================================================
$btnBrowse.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Selecione o diretorio onde deseja realizar a consulta de documentos:"
    $dialog.ShowNewFolderButton = $false

    $firstPath = ($txtDirectory.Text -split ';')[0].Trim()
    if (Test-Path $firstPath) {
        $dialog.SelectedPath = $firstPath
    }

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtDirectory.Text = $dialog.SelectedPath
        $txtStatus.Text = "Diretorio selecionado: " + $dialog.SelectedPath
    }
})

$btnSaveCurrent.Add_Click({
    $caminhoAtual = $txtDirectory.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($caminhoAtual)) {
        [System.Windows.MessageBox]::Show("Informe um caminho de diretório primeiro para salvar como atalho.", "Aviso", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        return
    }
    Open-GerenciadorAtalhos $caminhoAtual
})

$btnManageShortcuts.Add_Click({
    Open-GerenciadorAtalhos ""
})

# ==============================================================================
# FUNCAO FORMATAR TAMANHO
# ==============================================================================
function Format-FileSizeLocal([long]$bytes) {
    if ($bytes -ge 1GB) { return ("{0:N2} GB" -f ($bytes / 1GB)) }
    if ($bytes -ge 1MB) { return ("{0:N2} MB" -f ($bytes / 1MB)) }
    if ($bytes -ge 1KB) { return ("{0:N1} KB" -f ($bytes / 1KB)) }
    return ("{0} B" -f $bytes)
}

# ==============================================================================
# LOGICA DE BUSCA
# ==============================================================================
$ExecutarBusca = {
    $termo = $txtSearch.Text.Trim()
    $dirRaw = $txtDirectory.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($dirRaw)) {
        [System.Windows.MessageBox]::Show("Por favor, selecione ou informe ao menos um diretorio de consulta.", "Diretorio Nao Informado", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    $diretorios = $dirRaw -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    $recursivo = $chkRecursive.IsChecked

    # Filtro de extensoes
    $selectedCmb = $cmbExtension.Text
    $extensoesValidas = switch -Regex ($selectedCmb) {
        "Word"  { @(".docx", ".doc") }
        "PDF"   { @(".pdf") }
        "Excel" { @(".xlsx", ".xls", ".csv") }
        "Texto" { @(".txt", ".log") }
        default { $null }
    }

    # Bloqueia o botao enquanto busca
    $btnSearch.IsEnabled = $false
    $btnSearch.Content = "BUSCANDO..."
    $lstResults.Items.Clear()
    $txtStatus.Text = "Iniciando varredura..."
    $txtResultCount.Text = "Pesquisando..."
    [System.Windows.Forms.Application]::DoEvents()

    $totalEncontrados = 0
    $pastasInacessiveis = @()

    foreach ($dir in $diretorios) {
        if (!(Test-Path $dir)) {
            $pastasInacessiveis += $dir
            continue
        }

        $txtStatus.Text = "Consultando em: $dir"
        [System.Windows.Forms.Application]::DoEvents()

        $gciParams = @{
            Path        = $dir
            File        = $true
            ErrorAction = "SilentlyContinue"
        }

        if ($recursivo) {
            $gciParams["Recurse"] = $true
        }

        if ([string]::IsNullOrWhiteSpace($termo)) {
            $gciParams["Filter"] = "*.*"
        } else {
            $gciParams["Filter"] = "*$termo*.*"
        }

        $arquivos = Get-ChildItem @gciParams

        if ($arquivos) {
            foreach ($arq in $arquivos) {
                if ($extensoesValidas -ne $null) {
                    if ($extensoesValidas -notcontains $arq.Extension.ToLower()) {
                        continue
                    }
                }

                $totalEncontrados++
                $item = [PSCustomObject]@{
                    Name             = $arq.Name
                    FullName         = $arq.FullName
                    DirectoryName    = $arq.DirectoryName
                    LastWriteTime    = $arq.LastWriteTime
                    LastWriteTimeStr = $arq.LastWriteTime.ToString("dd/MM/yyyy HH:mm")
                    Length           = $arq.Length
                    SizeStr          = (Format-FileSizeLocal $arq.Length)
                }

                $lstResults.Items.Add($item)

                if ($totalEncontrados % 10 -eq 0) {
                    $txtResultCount.Text = "$totalEncontrados arquivo(s) encontrado(s)"
                    [System.Windows.Forms.Application]::DoEvents()
                }
            }
        }
    }

    # Re-aplica a ordenacao ativa se houver
    if (![string]::IsNullOrEmpty($script:lastSortProperty)) {
        $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($lstResults.Items)
        if ($view) {
            $view.SortDescriptions.Clear()
            $view.SortDescriptions.Add([System.ComponentModel.SortDescription]::new($script:lastSortProperty, $script:lastSortDirection))
            $view.Refresh()
        }
    }

    $btnSearch.IsEnabled = $true
    $btnSearch.Content = "PESQUISAR"
    $txtResultCount.Text = "$totalEncontrados arquivo(s) encontrado(s)"

    if ($pastasInacessiveis.Count -gt 0) {
        $txtStatus.Text = "Busca concluida ($totalEncontrados encontrados). Aviso: $($pastasInacessiveis.Count) pasta(s) nao acessivel(is)."
    } else {
        $txtStatus.Text = "Busca concluida com sucesso em $($diretorios.Count) diretorio(s)."
    }
}

$btnSearch.Add_Click($ExecutarBusca)

$txtSearch.Add_KeyDown({
    param($sender, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
        & $ExecutarBusca
    }
})

$txtDirectory.Add_KeyDown({
    param($sender, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
        & $ExecutarBusca
    }
})

# ==============================================================================
# ACOES COM O ITEM SELECIONADO
# ==============================================================================
$AbrirArquivoSelecionado = {
    $sel = $lstResults.SelectedItem
    if ($sel -and $sel.FullName) {
        if (Test-Path $sel.FullName) {
            Start-Process -FilePath $sel.FullName
        } else {
            [System.Windows.MessageBox]::Show("O arquivo selecionado nao foi encontrado no caminho especificado.", "Arquivo Inacessivel", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        }
    } else {
        [System.Windows.MessageBox]::Show("Nenhum arquivo selecionado na lista.", "Aviso", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
}

$AbrirPastaSelecionada = {
    $sel = $lstResults.SelectedItem
    if ($sel -and $sel.FullName) {
        if (Test-Path $sel.FullName) {
            Start-Process "explorer.exe" -ArgumentList "/select,`"$($sel.FullName)`""
        } elseif (Test-Path $sel.DirectoryName) {
            Start-Process "explorer.exe" -ArgumentList "`"$($sel.DirectoryName)`""
        } else {
            [System.Windows.MessageBox]::Show("A pasta selecionada nao esta acessivel no momento.", "Pasta Inacessivel", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        }
    } else {
        [System.Windows.MessageBox]::Show("Nenhum item selecionado na lista.", "Aviso", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
}

$CopiarCaminho = {
    $sel = $lstResults.SelectedItem
    if ($sel -and $sel.FullName) {
        [System.Windows.Clipboard]::SetText($sel.FullName)
        $txtStatus.Text = "Caminho copiado: " + $sel.FullName
    } else {
        [System.Windows.MessageBox]::Show("Nenhum item selecionado na lista.", "Aviso", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
}

$ExportarRelatorio = {
    if ($lstResults.Items.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Nao ha resultados para exportar.", "Aviso", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        return
    }

    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Title = "Salvar Relatorio de Busca - ArquivoNorte"
    $sfd.Filter = "Arquivo de Texto (*.txt)|*.txt|Arquivo CSV (*.csv)|*.csv"
    $sfd.FileName = "resultado_busca_arquivonorte_$(Get-Date -Format 'yyyyMMdd_HHmm').txt"

    if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $linhas = @()
        $linhas += "=========================================================="
        $linhas += " RELATORIO DE CONSULTA - ARQUIVONORTE"
        $linhas += " Data: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
        $linhas += " Termo de Busca: '$($txtSearch.Text)'"
        $linhas += " Diretorios Consultados: $($txtDirectory.Text)"
        $linhas += " Total Encontrado: $($lstResults.Items.Count)"
        $linhas += "=========================================================="
        $linhas += ""

        foreach ($item in $lstResults.Items) {
            $linhas += "[$($item.LastWriteTimeStr)] $($item.Name) ($($item.SizeStr))"
            $linhas += "   Pasta: $($item.DirectoryName)"
            $linhas += "   Caminho: $($item.FullName)"
            $linhas += ""
        }

        [System.IO.File]::WriteAllLines($sfd.FileName, $linhas, [System.Text.Encoding]::UTF8)
        $txtStatus.Text = "Relatorio exportado com sucesso para: " + $sfd.FileName
        [System.Windows.MessageBox]::Show("Relatorio salvo com sucesso!", "Exportacao Concluida", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
}

$lstResults.Add_MouseDoubleClick($AbrirArquivoSelecionado)
$btnOpenFile.Add_Click($AbrirArquivoSelecionado)
$btnOpenFolder.Add_Click($AbrirPastaSelecionada)
$btnCopyPath.Add_Click($CopiarCaminho)
$btnExport.Add_Click($ExportarRelatorio)

$txtSearch.Focus() | Out-Null

# Exibe a janela principal
$window.ShowDialog() | Out-Null
