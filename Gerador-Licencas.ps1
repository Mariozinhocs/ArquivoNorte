<#
.SYNOPSIS
    Gerador de Licenças Criptográficas - ArquivoNorte
    Painel de Administração exclusivo do Gestor (Mario Henrique).

.DESCRIPTION
    Emite chaves criptográficas com período de validade vinculado ao hardware
    da máquina de cada servidor (Node-Lock com HMAC-SHA256).
#>

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

$SecretSalt = "ArquivoNorte.A-Team.SecureHMAC.2026.MarioHenrique"

function Get-LocalMachineFingerprint {
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

function Generate-ArquivoNorteKey([string]$machineID, [int]$months = 3) {
    $cleanID = $machineID.Trim().ToUpper()
    if ($cleanID -notmatch '^AN-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}$') {
        return $null
    }

    $expDateTime = (Get-Date).AddMonths($months)
    $expDateStr = $expDateTime.ToString("yyyyMMdd")
    $payload = "$cleanID|$expDateStr"

    $hmac = [System.Security.Cryptography.HMACSHA256]::new([System.Text.Encoding]::UTF8.GetBytes($SecretSalt))
    $hashBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($payload))
    $sigHex = [System.BitConverter]::ToString($hashBytes).Replace("-", "")

    $key = "KEY-$expDateStr-" + $sigHex.Substring(0, 4) + "-" + $sigHex.Substring(4, 4)
    $expFormatada = $expDateTime.ToString("dd/MM/yyyy")

    $msg = "Olá! Sua licença do ArquivoNorte foi liberada.`r`n`r`n" +
           "📅 Validade: até $expFormatada ($months meses)`r`n" +
           "💻 ID Vinculado: $cleanID`r`n" +
           "🔑 Chave de Ativação: $key`r`n`r`n" +
           "Para ativar, abra o ArquivoNorte, cole a chave acima e clique em 'Ativar Aplicação'."

    return [PSCustomObject]@{
        Key        = $key
        Expiration = $expFormatada
        Message    = $msg
    }
}

[xml]$genXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Gerador de Licenças | ArquivoNorte - Painel do Gestor"
        Height="560" Width="640"
        MinHeight="500" MinWidth="520"
        WindowStartupLocation="CenterScreen"
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
            <DockPanel LastChildFill="True">
                <Border Background="#0E7490" CornerRadius="4" Padding="8,3" DockPanel.Dock="Right" VerticalAlignment="Center">
                    <TextBlock Text="GESTOR: MARIO HENRIQUE" Foreground="#ECFEFF" FontSize="10" FontWeight="Bold" />
                </Border>
                <StackPanel>
                    <TextBlock Text="🔑 Gerador de Licenças ArquivoNorte" FontSize="16" FontWeight="Bold" Foreground="#38BDF8" />
                    <TextBlock Text="Emita chaves criptográficas com validade vinculadas à máquina do servidor" FontSize="11" Foreground="#94A3B8" Margin="0,2,0,0" />
                </StackPanel>
            </DockPanel>
        </Border>

        <Border Grid.Row="1" Background="#1B1D22" BorderBrush="#2C2F36" BorderThickness="1" CornerRadius="8" Padding="14" Margin="0,0,0,14">
            <StackPanel>
                <TextBlock Text="ID DA MÁQUINA ENVIADO PELO USUÁRIO (ex: AN-XXXX-XXXX-XXXX-XXXX):" FontSize="11" FontWeight="Bold" Foreground="#06B6D4" Margin="0,0,0,4" />
                <Grid Margin="0,0,0,10">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*" />
                        <ColumnDefinition Width="Auto" />
                    </Grid.ColumnDefinitions>
                    <TextBox Name="txtMachineID" Background="#0F1013" Foreground="#F8FAFC" BorderBrush="#334155" FontSize="13" Padding="8,6" VerticalContentAlignment="Center" />
                    <Button Name="btnPaste" Grid.Column="1" Margin="8,0,0,0" Padding="12,6" Background="#272A30" Foreground="#E2E8F0" BorderBrush="#3F444E" Content="📋 Colar" Cursor="Hand" />
                </Grid>

                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*" />
                        <ColumnDefinition Width="Auto" />
                    </Grid.ColumnDefinitions>
                    <StackPanel Grid.Column="0">
                        <TextBlock Text="PERÍODO DE VALIDADE:" FontSize="11" FontWeight="Bold" Foreground="#06B6D4" Margin="0,0,0,4" />
                        <ComboBox Name="cmbDuration" Background="#0F1013" Foreground="#111827" Height="34" FontSize="12">
                            <ComboBoxItem Content="3 Meses (Padrão Recomendado)" IsSelected="True" />
                            <ComboBoxItem Content="6 Meses" />
                            <ComboBoxItem Content="1 Ano" />
                            <ComboBoxItem Content="30 Dias (Período de Teste)" />
                        </ComboBox>
                    </StackPanel>
                    <Button Name="btnGenerate" Grid.Column="1" Margin="12,18,0,0" Padding="20,0" Height="34" Background="#0284C7" Foreground="White" FontWeight="Bold" BorderThickness="0" Content="⚡ GERAR CHAVE" Cursor="Hand" />
                </Grid>
            </StackPanel>
        </Border>

        <Border Grid.Row="2" Background="#1B1D22" BorderBrush="#2C2F36" BorderThickness="1" CornerRadius="8" Padding="14" Margin="0,0,0,14">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto" />
                    <RowDefinition Height="Auto" />
                    <RowDefinition Height="Auto" />
                    <RowDefinition Height="*" />
                </Grid.RowDefinitions>

                <TextBlock Grid.Row="0" Text="CHAVE GERADA:" FontSize="11" FontWeight="Bold" Foreground="#06B6D4" Margin="0,0,0,4" />
                <Grid Grid.Row="1" Margin="0,0,0,10">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*" />
                        <ColumnDefinition Width="Auto" />
                    </Grid.ColumnDefinitions>
                    <TextBox Name="txtGeneratedKey" IsReadOnly="True" Background="#0F1013" Foreground="#10B981" FontWeight="Bold" FontSize="14" Padding="8,6" VerticalContentAlignment="Center" />
                    <Button Name="btnCopyKey" Grid.Column="1" Margin="8,0,0,0" Padding="14,6" Background="#272A30" Foreground="#E2E8F0" BorderBrush="#3F444E" Content="📋 Copiar Chave" Cursor="Hand" />
                </Grid>

                <TextBlock Grid.Row="2" Text="MENSAGEM FORMATADA PARA O WHATSAPP / EMAIL:" FontSize="11" FontWeight="Bold" Foreground="#06B6D4" Margin="0,0,0,4" />
                <TextBox Name="txtMessage" Grid.Row="3" IsReadOnly="True" Background="#0F1013" Foreground="#94A3B8" BorderBrush="#334155" FontSize="12" Padding="8" TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" />
            </Grid>
        </Border>

        <DockPanel Grid.Row="3" LastChildFill="False">
            <Button Name="btnCopyMsg" DockPanel.Dock="Right" Padding="14,7" Background="#059669" Foreground="White" FontWeight="Bold" BorderThickness="0" Content="💬 Copiar Mensagem WhatsApp" Cursor="Hand" />
            <Button Name="btnSelfActivate" DockPanel.Dock="Left" Padding="12,7" Background="#1E293B" Foreground="#38BDF8" BorderBrush="#0369A1" Content="🛡️ Ativar Meu Próprio Computador" Cursor="Hand" />
        </DockPanel>
    </Grid>
</Window>
'@

$reader = (New-Object System.Xml.XmlNodeReader $genXaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Carrega icone se disponivel
$iconPath = Join-Path $PSScriptRoot "icon_ArquivoNorte.png"
if (Test-Path $iconPath) {
    try {
        $uri = New-Object System.Uri($iconPath, [System.UriKind]::Absolute)
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit()
        $bmp.UriSource = $uri
        $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bmp.EndInit()
        $window.Icon = $bmp
    } catch {}
}

$txtMachineID    = $window.FindName("txtMachineID")
$btnPaste        = $window.FindName("btnPaste")
$cmbDuration     = $window.FindName("cmbDuration")
$btnGenerate     = $window.FindName("btnGenerate")
$txtGeneratedKey = $window.FindName("txtGeneratedKey")
$btnCopyKey      = $window.FindName("btnCopyKey")
$txtMessage      = $window.FindName("txtMessage")
$btnCopyMsg      = $window.FindName("btnCopyMsg")
$btnSelfActivate = $window.FindName("btnSelfActivate")

$btnPaste.Add_Click({
    $clip = [System.Windows.Clipboard]::GetText()
    if (![string]::IsNullOrWhiteSpace($clip)) {
        $txtMachineID.Text = $clip.Trim()
    }
})

$ExecutarGeracao = {
    $mid = $txtMachineID.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($mid)) {
        [System.Windows.MessageBox]::Show("Por favor, informe ou cole o ID da máquina.", "Aviso", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    $meses = switch -Regex ($cmbDuration.Text) {
        "1 Ano"   { 12 }
        "6 Meses" { 6 }
        "30 Dias" { 1 }
        default   { 3 }
    }

    $res = Generate-ArquivoNorteKey $mid $meses
    if ($res -eq $null) {
        [System.Windows.MessageBox]::Show("O ID informado não possui um formato válido (Ex: AN-XXXX-XXXX-XXXX-XXXX).", "Formato Inválido", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        return
    }

    $txtGeneratedKey.Text = $res.Key
    $txtMessage.Text = $res.Message

    [System.Windows.Clipboard]::SetText($res.Key)
    [System.Windows.MessageBox]::Show("Chave gerada com sucesso e copiada para a Área de Transferência!`r`n`r`nChave: $($res.Key)`r`nValidade: $($res.Expiration)", "Chave Pronta", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
}

$btnGenerate.Add_Click($ExecutarGeracao)

$btnCopyKey.Add_Click({
    if (![string]::IsNullOrWhiteSpace($txtGeneratedKey.Text)) {
        [System.Windows.Clipboard]::SetText($txtGeneratedKey.Text)
        [System.Windows.MessageBox]::Show("Chave copiada para a Área de Transferência!", "Copiado", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
})

$btnCopyMsg.Add_Click({
    if (![string]::IsNullOrWhiteSpace($txtMessage.Text)) {
        [System.Windows.Clipboard]::SetText($txtMessage.Text)
        [System.Windows.MessageBox]::Show("Mensagem completa copiada! Basta colar no WhatsApp ou Email.", "Copiado", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
})

$btnSelfActivate.Add_Click({
    $localID = Get-LocalMachineFingerprint
    $res = Generate-ArquivoNorteKey $localID 12

    $appData = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)
    $targetDir = Join-Path $appData "ArquivoNorte"
    if (!(Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
    $licFile = Join-Path $targetDir "licenca.lic"

    [System.IO.File]::WriteAllText($licFile, $res.Key, [System.Text.Encoding]::UTF8)

    [System.Windows.MessageBox]::Show("Seu computador foi ativado com sucesso por 1 ano!`r`n`r`nID desta máquina: $localID`r`nChave: $($res.Key)", "Ativação Concluída", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
})

$window.ShowDialog() | Out-Null
