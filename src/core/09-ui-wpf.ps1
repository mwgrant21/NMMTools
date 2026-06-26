# WPF GUI layer. Loaded only when the user selects GUI mode at startup.
# Requires PS 5.1 on an STA-capable thread (handled by Start-GuiMenu).
# All WPF control access happens on the STA/UI thread. All tool execution
# happens in a long-lived Runspace; output is marshalled via Dispatcher.

# ---- Category color map (hex strings matching the spec) -----------------
$script:CategoryColors = @{
    'Browser'      = '#E0E0E0'
    'Cloud'        = '#FFCA28'
    'Diagnostics'  = '#4FC3F7'
    'Laptop'       = '#66BB6A'
    'QuickFix'     = '#CE93D8'
    'Repair'       = '#EF5350'
    'Security'     = '#C9A227'
    'User'         = '#5C8DDF'
    'Common Fixes' = '#FFFFFF'
}

# ---- XAML definitions ---------------------------------------------------

$script:MainWindowXaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="NMM Toolkit v9"
    MinWidth="900" MinHeight="580" Width="1200" Height="750"
    Background="#1E1E1E" Foreground="#CCCCCC"
    WindowStartupLocation="CenterScreen">
  <Window.Resources>
    <Style TargetType="ScrollBar">
      <Setter Property="Background" Value="#2D2D30"/>
    </Style>
    <Style TargetType="Button" x:Key="NavButtonStyle">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="#CCCCCC"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Padding" Value="12,8,8,8"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderThickness="0">
              <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"
                                Margin="{TemplateBinding Padding}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#323235"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#3E3E42"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="Button" x:Key="RunButtonStyle">
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="16,6,16,6"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style TargetType="Button" x:Key="GhostButtonStyle">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="#858585"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="BorderBrush" Value="#3E3E42"/>
      <Setter Property="Padding" Value="10,4,10,4"/>
      <Setter Property="Cursor" Value="Hand"/>
    </Style>
    <Style TargetType="TextBox" x:Key="SearchBoxStyle">
      <Setter Property="Background" Value="#3E3E42"/>
      <Setter Property="Foreground" Value="#CCCCCC"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="8,4,8,4"/>
      <Setter Property="CaretBrush" Value="#CCCCCC"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>
    <Style TargetType="ListBoxItem">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="#CCCCCC"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="8,4,8,4"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="Bd" Background="{TemplateBinding Background}"
                    BorderThickness="2,0,0,0" BorderBrush="Transparent">
              <ContentPresenter HorizontalAlignment="Stretch"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#2A2A2E"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#2A2A2E"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="#4FC3F7"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="40"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="4"/>
    </Grid.RowDefinitions>

    <!-- Header Bar -->
    <Border Grid.Row="0" Background="#2D2D30" BorderBrush="#3E3E42" BorderThickness="0,0,0,1">
      <Grid Margin="12,0,12,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="8"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="8"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock Grid.Column="0" Text="NMM Toolkit v9" FontWeight="SemiBold"
                   Foreground="#CCCCCC" VerticalAlignment="Center" FontSize="13"/>
        <TextBlock Grid.Column="2" x:Name="MachineUserLabel" Foreground="#858585"
                   VerticalAlignment="Center" FontSize="11"/>
        <Border Grid.Column="4" x:Name="AdminBadge" CornerRadius="3"
                Padding="6,2,6,2" VerticalAlignment="Center">
          <TextBlock x:Name="AdminBadgeText" FontSize="11" FontWeight="SemiBold"/>
        </Border>
        <TextBlock Grid.Column="6" x:Name="SessionTimerLabel" Foreground="#858585"
                   VerticalAlignment="Center" FontSize="11"/>
      </Grid>
    </Border>

    <!-- Main 3-pane layout -->
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="180" MinWidth="140"/>
        <ColumnDefinition Width="4"/>
        <ColumnDefinition Width="280" MinWidth="200"/>
        <ColumnDefinition Width="4"/>
        <ColumnDefinition Width="*" MinWidth="300"/>
      </Grid.ColumnDefinitions>

      <!-- Left nav -->
      <Border Grid.Column="0" Background="#252526" BorderBrush="#3E3E42" BorderThickness="0,0,1,0">
        <StackPanel x:Name="CategoryNavPanel" Margin="0,8,0,8"/>
      </Border>

      <GridSplitter Grid.Column="1" Width="4" HorizontalAlignment="Stretch"
                    Background="#3E3E42" ResizeBehavior="PreviousAndNext"/>

      <!-- Tool list -->
      <Border Grid.Column="2" Background="#2D2D30" BorderBrush="#3E3E42" BorderThickness="0,0,1,0">
        <DockPanel>
          <!-- Search -->
          <Border DockPanel.Dock="Top" Background="#2D2D30" Padding="8,6,8,6"
                  BorderBrush="#3E3E42" BorderThickness="0,0,0,1">
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <TextBox Grid.Column="0" x:Name="SearchBox" Style="{StaticResource SearchBoxStyle}"
                       Height="26" VerticalContentAlignment="Center"/>
              <Button Grid.Column="1" x:Name="SearchClearButton" Content="x"
                      Style="{StaticResource GhostButtonStyle}"
                      Margin="4,0,0,0" Height="26" Visibility="Collapsed"/>
            </Grid>
          </Border>
          <ListBox x:Name="ToolListBox" Background="#2D2D30" BorderThickness="0"
                   Foreground="#CCCCCC" ScrollViewer.HorizontalScrollBarVisibility="Disabled"
                   VirtualizingStackPanel.IsVirtualizing="True"
                   VirtualizingStackPanel.VirtualizationMode="Recycling"/>
        </DockPanel>
      </Border>

      <GridSplitter Grid.Column="3" Width="4" HorizontalAlignment="Stretch"
                    Background="#3E3E42" ResizeBehavior="PreviousAndNext"/>

      <!-- Right panel: detail card + output pane -->
      <Grid Grid.Column="4">
        <Grid.RowDefinitions>
          <RowDefinition Height="220" MinHeight="120"/>
          <RowDefinition Height="4"/>
          <RowDefinition Height="*" MinHeight="150"/>
        </Grid.RowDefinitions>

        <!-- Tool detail card -->
        <Border Grid.Row="0" Background="#252526" BorderBrush="#3E3E42" BorderThickness="0,0,0,1">
          <Grid Margin="16,12,16,12">
            <!-- Placeholder when nothing selected -->
            <TextBlock x:Name="ToolDetailPlaceholder" Text="Select a tool to see its details."
                       Foreground="#505050" VerticalAlignment="Center" HorizontalAlignment="Center"
                       FontSize="13"/>

            <!-- Actual detail card (hidden until a tool is selected) -->
            <DockPanel x:Name="ToolDetailCard" Visibility="Collapsed">
              <DockPanel DockPanel.Dock="Bottom" LastChildFill="False" Margin="0,8,0,0">
                <!-- Run button -->
                <Button x:Name="RunButton" DockPanel.Dock="Left" Content="Run"
                        Style="{StaticResource RunButtonStyle}" MinWidth="80"/>
                <TextBlock x:Name="AdminRefusedLabel" DockPanel.Dock="Left"
                           Text="Requires admin - re-launch elevated"
                           Foreground="#F44747" VerticalAlignment="Center"
                           Margin="8,0,0,0" Visibility="Collapsed"/>
              </DockPanel>

              <!-- Confirm banner for Modifies tools -->
              <Border x:Name="ConfirmBanner" DockPanel.Dock="Bottom" Visibility="Collapsed"
                      Background="#1E1E1E" BorderBrush="#FFCA28" BorderThickness="4,0,0,0"
                      Margin="0,8,0,0" Padding="12,8,8,8">
                <DockPanel>
                  <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
                    <Button x:Name="ConfirmRunButton" Content="Run" Background="#FF9800"
                            Foreground="#000000" BorderThickness="0" Padding="12,4,12,4"
                            Cursor="Hand" Margin="0,0,8,0"/>
                    <Button x:Name="ConfirmCancelButton" Content="Cancel"
                            Style="{StaticResource GhostButtonStyle}"/>
                  </StackPanel>
                  <TextBlock x:Name="ConfirmBannerText"
                             Text="This tool modifies system settings. Review the description above before proceeding."
                             Foreground="#FFCA28" TextWrapping="Wrap" VerticalAlignment="Center"/>
                </DockPanel>
              </Border>

              <DockPanel DockPanel.Dock="Top">
                <TextBlock x:Name="ToolNameLabel" DockPanel.Dock="Top" FontSize="15"
                           FontWeight="SemiBold" Foreground="#CCCCCC" TextWrapping="Wrap"
                           Margin="0,0,0,6"/>
                <!-- Chips row -->
                <WrapPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,8">
                  <Border x:Name="RiskChip" CornerRadius="3" Padding="6,2,6,2" Margin="0,0,6,0">
                    <TextBlock x:Name="RiskChipText" FontSize="11" FontWeight="SemiBold"/>
                  </Border>
                  <Border x:Name="AdminChip" Background="#1A2530" CornerRadius="3"
                          Padding="6,2,6,2" Margin="0,0,6,0" Visibility="Collapsed">
                    <TextBlock Text="Admin Required" Foreground="#4FC3F7" FontSize="11"/>
                  </Border>
                  <Border x:Name="CategoryChip" CornerRadius="3" Padding="6,2,6,2"
                          BorderThickness="1" Margin="0,0,6,0">
                    <TextBlock x:Name="CategoryChipText" FontSize="11"/>
                  </Border>
                </WrapPanel>
                <TextBlock x:Name="DescriptionLabel" DockPanel.Dock="Top"
                           Foreground="#858585" FontSize="12" TextWrapping="Wrap"
                           Margin="0,0,0,8"/>
                <!-- Tags -->
                <WrapPanel x:Name="TagsPanel" DockPanel.Dock="Top" Orientation="Horizontal"/>
              </DockPanel>
            </DockPanel>
          </Grid>
        </Border>

        <GridSplitter Grid.Row="1" Height="4" HorizontalAlignment="Stretch"
                      Background="#3E3E42" ResizeBehavior="PreviousAndNext"/>

        <!-- Output pane -->
        <Grid Grid.Row="2">
          <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <!-- Output box with scroll-to-bottom overlay -->
          <Grid Grid.Row="0">
            <RichTextBox x:Name="OutputBox" IsReadOnly="True" IsDocumentEnabled="False"
                         Background="#0C0C0C" Foreground="#CCCCCC"
                         FontFamily="Consolas" FontSize="11"
                         HorizontalScrollBarVisibility="Disabled"
                         VerticalScrollBarVisibility="Auto"
                         BorderThickness="0" Padding="6,4,6,4">
              <RichTextBox.Document>
                <FlowDocument PagePadding="6,4,6,4" LineHeight="16"
                              Background="#0C0C0C" Foreground="#CCCCCC"
                              FontFamily="Consolas" FontSize="11"/>
              </RichTextBox.Document>
            </RichTextBox>
            <!-- Placeholder text when empty -->
            <TextBlock x:Name="OutputPlaceholder"
                       Text="No output yet - run a tool to begin."
                       Foreground="#505050" FontFamily="Consolas" FontSize="11"
                       VerticalAlignment="Top" HorizontalAlignment="Left"
                       Margin="12,8,0,0" IsHitTestVisible="False"/>
            <!-- Scroll to bottom overlay button -->
            <Button x:Name="ScrollToBottomButton" Content="v Bottom"
                    VerticalAlignment="Bottom" HorizontalAlignment="Right"
                    Margin="0,0,20,10" Padding="8,4,8,4"
                    Background="#2D2D30" Foreground="#858585"
                    BorderBrush="#3E3E42" BorderThickness="1"
                    Cursor="Hand" Visibility="Collapsed"/>
          </Grid>

          <!-- Prompt area (slides up when Read-ToolChoice is pending) -->
          <Border Grid.Row="1" x:Name="PromptArea" Visibility="Collapsed"
                  Background="#1A2530" BorderBrush="#4FC3F7" BorderThickness="0,3,0,0"
                  Padding="12,8,12,8">
            <DockPanel>
              <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,6">
                <TextBlock x:Name="PromptTextBlock" Foreground="#CCCCCC" FontSize="12"
                           FontWeight="SemiBold" VerticalAlignment="Center"/>
                <TextBlock x:Name="PromptDefaultLabel" Foreground="#858585" FontSize="11"
                           VerticalAlignment="Center" Margin="8,0,0,0"/>
              </StackPanel>
              <WrapPanel x:Name="ChoiceButtonsPanel" Orientation="Horizontal"/>
            </DockPanel>
          </Border>
        </Grid>
      </Grid>
    </Grid>

    <!-- Status bar -->
    <Border Grid.Row="2" Background="#2D2D30" BorderBrush="#3E3E42"
            BorderThickness="0,1,0,0" Height="28">
      <DockPanel Margin="8,0,8,0">
        <Button x:Name="ExportTicketButton" DockPanel.Dock="Right"
                Content="Export Ticket" Style="{StaticResource GhostButtonStyle}"
                Margin="8,0,0,0" Height="22" VerticalAlignment="Center"/>
        <Button x:Name="ClearOutputButton" DockPanel.Dock="Right"
                Content="Clear Output" Style="{StaticResource GhostButtonStyle}"
                Margin="8,0,0,0" Height="22" VerticalAlignment="Center"/>
        <Button x:Name="CopyOutputButton" DockPanel.Dock="Right"
                Content="Copy Output" Style="{StaticResource GhostButtonStyle}"
                Margin="8,0,0,0" Height="22" VerticalAlignment="Center"/>
        <TextBlock x:Name="StatusLabel" DockPanel.Dock="Left"
                   Foreground="#858585" VerticalAlignment="Center" FontSize="11"
                   Text="Idle"/>
      </DockPanel>
    </Border>

    <!-- Progress bar (full width, above status bar, visible only during run) -->
    <ProgressBar Grid.Row="3" x:Name="RunProgressBar"
                 IsIndeterminate="True" Height="4"
                 Background="#1E1E1E" Foreground="#4FC3F7"
                 BorderThickness="0" Visibility="Collapsed"/>
  </Grid>
</Window>
'@

$script:ConfirmDialogXaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Confirm Disruptive Operation"
    Width="480" Height="280" ResizeMode="NoResize"
    WindowStartupLocation="CenterOwner"
    Background="#1E1E1E" Foreground="#CCCCCC">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="48"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Border Grid.Row="0" Background="#C62828">
      <TextBlock x:Name="DialogHeader" Foreground="#FFFFFF" FontWeight="Bold"
                 FontSize="13" VerticalAlignment="Center" Margin="16,0,16,0"
                 TextTrimming="CharacterEllipsis"/>
    </Border>
    <StackPanel Grid.Row="1" Margin="16,16,16,8">
      <TextBlock x:Name="DialogDescription" Foreground="#CCCCCC" TextWrapping="Wrap"
                 FontSize="12" Margin="0,0,0,12"/>
      <TextBlock Text="This operation cannot be easily undone. Type CONFIRM below to proceed."
                 Foreground="#F44747" FontSize="12" TextWrapping="Wrap" Margin="0,0,0,8"/>
      <TextBox x:Name="ConfirmTextBox" Background="#2D2D30" Foreground="#FFFFFF"
               BorderBrush="#3E3E42" BorderThickness="1" Padding="8,6,8,6"
               FontSize="13" CaretBrush="#FFFFFF"/>
    </StackPanel>
    <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right"
                Margin="16,0,16,16">
      <Button x:Name="ProceedButton" Content="Proceed" IsEnabled="False"
              Background="#C62828" Foreground="#FFFFFF" BorderThickness="0"
              Padding="16,6,16,6" Margin="0,0,8,0" Cursor="Hand" FontWeight="SemiBold"/>
      <Button x:Name="CancelButton" Content="Cancel"
              Background="#3E3E42" Foreground="#CCCCCC" BorderThickness="0"
              Padding="12,6,12,6" Cursor="Hand"/>
    </StackPanel>
  </Grid>
</Window>
'@

$script:TicketExportDialogXaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Export Ticket Summary"
    Width="580" Height="480" MinWidth="400" MinHeight="300"
    WindowStartupLocation="CenterOwner"
    Background="#1E1E1E" Foreground="#CCCCCC">
  <Grid Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBox Grid.Row="0" x:Name="TicketTextBox" IsReadOnly="True"
             Background="#0C0C0C" Foreground="#CCCCCC" BorderThickness="1"
             BorderBrush="#3E3E42" FontFamily="Consolas" FontSize="11"
             AcceptsReturn="True" TextWrapping="Wrap"
             VerticalScrollBarVisibility="Auto" Padding="8"/>
    <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,8,0,4">
      <Button x:Name="CopyButton" Content="Copy to Clipboard"
              Background="#2E7D32" Foreground="#FFFFFF" BorderThickness="0"
              Padding="14,6,14,6" Cursor="Hand" Margin="0,0,8,0" FontWeight="SemiBold"/>
      <Button x:Name="SaveButton" Content="Save to Desktop"
              Background="#3E3E42" Foreground="#CCCCCC" BorderThickness="0"
              Padding="14,6,14,6" Cursor="Hand" Margin="0,0,8,0"/>
      <Button x:Name="CloseButton" Content="Close"
              Background="#3E3E42" Foreground="#CCCCCC" BorderThickness="0"
              Padding="14,6,14,6" Cursor="Hand"/>
    </StackPanel>
    <TextBlock Grid.Row="2" x:Name="SaveStatusLabel" Foreground="#858585"
               FontSize="11" TextWrapping="Wrap"/>
  </Grid>
</Window>
'@

# ---- Helper: parse hex color string to WPF Color -------------------------
function ConvertTo-WpfColor {
    param([string]$Hex)
    $h = $Hex.TrimStart('#')
    if ($h.Length -eq 6) { $h = 'FF' + $h }
    $a = [Convert]::ToInt32($h.Substring(0,2), 16)
    $r = [Convert]::ToInt32($h.Substring(2,2), 16)
    $g = [Convert]::ToInt32($h.Substring(4,2), 16)
    $b = [Convert]::ToInt32($h.Substring(6,2), 16)
    return [System.Windows.Media.Color]::FromArgb($a, $r, $g, $b)
}

function ConvertTo-WpfBrush {
    param([string]$Hex)
    return [System.Windows.Media.SolidColorBrush]::new((ConvertTo-WpfColor $Hex))
}

# ---- Run button color by risk -------------------------------------------
function Get-RunButtonColor {
    param([string]$Risk)
    switch ($Risk) {
        'Disruptive' { return '#C62828' }
        'Modifies'   { return '#E65100' }
        default      { return '#2E7D32' }
    }
}

# ---- Populate ToolListBox -----------------------------------------------
function Update-ToolList {
    param($Window)
    $sync    = $script:GuiSync
    $listBox = $sync.ToolListBox
    $listBox.Items.Clear()
    $sync.OutputPlaceholder.Visibility = [System.Windows.Visibility]::Visible

    $searchTerm = $sync.SearchBox.Text.Trim()
    if ($searchTerm.Length -gt 0) {
        $tools = @(Search-NmmTools -Term $searchTerm)
    } elseif ($sync.SelectedCategory -eq 'Common Fixes') {
        $tools = @(Get-NmmCommonFixes -Max 6)
        if ($tools.Count -eq 0) {
            $item = [System.Windows.Controls.ListBoxItem]::new()
            $item.Content = 'No tools have been run yet. Use any tool once to start tracking favorites.'
            $item.Foreground = ConvertTo-WpfBrush '#505050'
            $item.IsEnabled = $false
            [void]$listBox.Items.Add($item)
            return
        }
    } else {
        $cat   = $sync.SelectedCategory
        $tools = @(Get-NmmTools | Where-Object { $_.Category -eq $cat } |
                   Sort-Object { Get-NmmLegacyIdSortKey $_.LegacyId })
    }

    if ($tools.Count -eq 0) {
        $item = [System.Windows.Controls.ListBoxItem]::new()
        $item.Content   = if ($searchTerm) { "No tools match '$searchTerm'" } else { 'No tools in this category.' }
        $item.Foreground = ConvertTo-WpfBrush '#505050'
        $item.IsEnabled  = $false
        [void]$listBox.Items.Add($item)
        return
    }

    foreach ($tool in $tools) {
        $item = [System.Windows.Controls.ListBoxItem]::new()
        $item.Tag = $tool

        # Build the item content as a DockPanel
        $dp = [System.Windows.Controls.DockPanel]::new()
        $dp.LastChildFill = $true

        # Right side: risk badge + admin triangle
        $badge = ''
        if ($tool.Risk -eq 'Modifies')   { $badge = '[M]' }
        if ($tool.Risk -eq 'Disruptive') { $badge = '[!]' }
        if ($tool.RequiresAdmin)          { $badge += [char]0x25B2 }

        if ($badge) {
            $badgeColor = if ($tool.Risk -eq 'Disruptive') { '#EF5350' }
                          elseif ($tool.Risk -eq 'Modifies') { '#FFCA28' }
                          else { '#858585' }
            $badgeTb = [System.Windows.Controls.TextBlock]::new()
            $badgeTb.Text       = $badge
            $badgeTb.Foreground = ConvertTo-WpfBrush $badgeColor
            $badgeTb.FontSize   = 10
            $badgeTb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            $badgeTb.Margin = [System.Windows.Thickness]::new(4,0,0,0)
            [System.Windows.Controls.DockPanel]::SetDock($badgeTb, [System.Windows.Controls.Dock]::Right)
            [void]$dp.Children.Add($badgeTb)
        }

        $nameTb = [System.Windows.Controls.TextBlock]::new()
        $nameTb.Text = ('{0,4}. {1}' -f $tool.LegacyId, $tool.Name)
        $nameTb.Foreground = ConvertTo-WpfBrush '#CCCCCC'
        $nameTb.FontSize   = 12
        $nameTb.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        $nameTb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        [void]$dp.Children.Add($nameTb)

        $item.Content = $dp
        [void]$listBox.Items.Add($item)
    }
}

# ---- Populate detail card -----------------------------------------------
function Update-DetailCard {
    param([hashtable]$Tool)
    $sync = $script:GuiSync

    $sync.ToolDetailPlaceholder.Visibility = [System.Windows.Visibility]::Collapsed
    $sync.ToolDetailCard.Visibility        = [System.Windows.Visibility]::Visible

    $sync.ToolNameLabel.Text = $Tool.Name

    # Risk chip
    switch ($Tool.Risk) {
        'Disruptive' {
            $sync.RiskChip.Background = ConvertTo-WpfBrush '#4A1E1E'
            $sync.RiskChipText.Text       = '[!] Disruptive'
            $sync.RiskChipText.Foreground = ConvertTo-WpfBrush '#F44747'
        }
        'Modifies' {
            $sync.RiskChip.Background = ConvertTo-WpfBrush '#4A3E1A'
            $sync.RiskChipText.Text       = '[M] Modifies'
            $sync.RiskChipText.Foreground = ConvertTo-WpfBrush '#FFCA28'
        }
        default {
            $sync.RiskChip.Background = ConvertTo-WpfBrush '#2E4A2E'
            $sync.RiskChipText.Text       = 'ReadOnly'
            $sync.RiskChipText.Foreground = ConvertTo-WpfBrush '#4EC94E'
        }
    }

    # Admin chip
    $sync.AdminChip.Visibility = if ($Tool.RequiresAdmin) {
        [System.Windows.Visibility]::Visible
    } else {
        [System.Windows.Visibility]::Collapsed
    }

    # Category chip
    $catColor = if ($script:CategoryColors.ContainsKey($Tool.Category)) {
        $script:CategoryColors[$Tool.Category]
    } else { '#858585' }
    $sync.CategoryChip.BorderBrush = ConvertTo-WpfBrush $catColor
    $sync.CategoryChipText.Text       = $Tool.Category
    $sync.CategoryChipText.Foreground = ConvertTo-WpfBrush $catColor

    $sync.DescriptionLabel.Text = $Tool.Description

    # Tags
    $sync.TagsPanel.Children.Clear()
    foreach ($tag in $Tool.Tags) {
        $border = [System.Windows.Controls.Border]::new()
        $border.Background     = ConvertTo-WpfBrush '#2D2D30'
        $border.BorderBrush    = ConvertTo-WpfBrush '#3E3E42'
        $border.BorderThickness = [System.Windows.Thickness]::new(1)
        $border.CornerRadius   = [System.Windows.CornerRadius]::new(3)
        $border.Padding        = [System.Windows.Thickness]::new(6,1,6,1)
        $border.Margin         = [System.Windows.Thickness]::new(0,0,4,4)
        $tb = [System.Windows.Controls.TextBlock]::new()
        $tb.Text     = $tag
        $tb.Foreground = ConvertTo-WpfBrush '#858585'
        $tb.FontSize = 10
        $border.Child = $tb
        [void]$sync.TagsPanel.Children.Add($border)
    }

    # Run button vs admin refused
    $runColor = Get-RunButtonColor -Risk $Tool.Risk
    $sync.RunButton.Background = ConvertTo-WpfBrush $runColor

    if ($Tool.RequiresAdmin -and -not $script:IsAdmin) {
        $sync.RunButton.Visibility        = [System.Windows.Visibility]::Collapsed
        $sync.AdminRefusedLabel.Visibility = [System.Windows.Visibility]::Visible
    } else {
        $sync.RunButton.Visibility         = [System.Windows.Visibility]::Visible
        $sync.AdminRefusedLabel.Visibility = [System.Windows.Visibility]::Collapsed
    }
    $sync.ConfirmBanner.Visibility = [System.Windows.Visibility]::Collapsed

    $sync.SelectedTool = $Tool
}

# ---- Set running state (UI thread) --------------------------------------
function Set-GuiRunning {
    param([hashtable]$Tool)
    $sync = $script:GuiSync
    $sync.RunState                        = 'Running'
    $sync.RunButton.IsEnabled             = $false
    $sync.ToolListBox.IsEnabled           = $false
    $sync.CategoryNavPanel.IsEnabled      = $false
    $sync.ExportTicketButton.IsEnabled    = $false
    $sync.RunProgressBar.Visibility       = [System.Windows.Visibility]::Visible
    $sync.StatusLabel.Text                = ('Running: {0}...' -f $Tool.Name)
    $sync.StatusLabel.Foreground          = ConvertTo-WpfBrush '#CCCCCC'
    $sync.OutputPlaceholder.Visibility    = [System.Windows.Visibility]::Collapsed
}

# ---- Clear running state (UI thread) ------------------------------------
function Set-GuiIdle {
    param([string]$ToolName, [string]$Status)
    $sync = $script:GuiSync
    $sync.RunState                        = 'Idle'
    $sync.RunButton.IsEnabled             = $true
    $sync.ToolListBox.IsEnabled           = $true
    $sync.CategoryNavPanel.IsEnabled      = $true
    $sync.ExportTicketButton.IsEnabled    = $true
    $sync.RunProgressBar.Visibility       = [System.Windows.Visibility]::Collapsed
    $sync.PromptArea.Visibility           = [System.Windows.Visibility]::Collapsed

    $statusColor = switch ($Status) {
        'Success' { '#4EC94E' }
        'Failed'  { '#F44747' }
        'Warning' { '#FFCA28' }
        default   { '#858585' }
    }
    $sync.StatusLabel.Text       = ('Last run: {0} - {1}' -f $ToolName, $Status.ToUpper())
    $sync.StatusLabel.Foreground = ConvertTo-WpfBrush $statusColor

    # If semaphore leaked (tool crashed mid-prompt), reset it
    if ($sync.PromptArea.Visibility -ne [System.Windows.Visibility]::Collapsed) {
        $sync.PromptArea.Visibility = [System.Windows.Visibility]::Collapsed
    }
    if ($sync.PromptSemaphore.CurrentCount -eq 0) {
        try { [void]$sync.PromptSemaphore.Release() } catch { }
        $sync.PromptSemaphore = [System.Threading.SemaphoreSlim]::new(0, 1)
    }
}

# ---- Runspace factory ---------------------------------------------------
function New-NmmToolRunspace {
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    Get-ChildItem Function: | Where-Object { $null -eq $_.Module } | ForEach-Object {
        try {
            $entry = [System.Management.Automation.Runspaces.SessionStateFunctionEntry]::new(
                $_.Name, $_.Definition)
            $iss.Commands.Add($entry)
        } catch { }
    }
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
    $rs.Open()
    return $rs
}

# ---- Tool execution (UI thread entry, actual work in Runspace) ----------
function Invoke-GuiToolRun {
    param([hashtable]$Tool)
    $sync = $script:GuiSync

    Set-GuiRunning -Tool $Tool
    $sync.ConfirmBanner.Visibility = [System.Windows.Visibility]::Collapsed

    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $sync.ToolRunspace

    $registryData = $script:RegistryData
    $toolRuns     = $script:ToolRuns
    $sessionStart = $script:SessionStart
    $isAdmin      = $script:IsAdmin
    $logFilePath  = $script:LogFilePath

    [void]$ps.AddScript({
        param($Tool, $GuiSync, $RegistryData, $ToolRuns, $SessionStart, $IsAdmin, $LogFilePath)

        $script:OutputSink              = 'GUI'
        $script:GuiSync                 = $GuiSync
        $script:RegistryData            = $RegistryData
        $script:ToolRuns                = $ToolRuns
        $script:SessionStart            = $SessionStart
        $script:IsAdmin                 = $IsAdmin
        $script:LogFilePath             = $LogFilePath
        $script:UsageFilePathOverride   = $null

        Invoke-NmmTool -Tool $Tool | Out-Null
        Add-NmmUsage -Id $Tool.Id

    })
    [void]$ps.AddParameter('Tool',         $Tool        )
    [void]$ps.AddParameter('GuiSync',      $sync        )
    [void]$ps.AddParameter('RegistryData', $registryData)
    [void]$ps.AddParameter('ToolRuns',     $toolRuns    )
    [void]$ps.AddParameter('SessionStart', $sessionStart)
    [void]$ps.AddParameter('IsAdmin',      $isAdmin     )
    [void]$ps.AddParameter('LogFilePath',  $logFilePath )

    $handle = $ps.BeginInvoke()

    $capturedPs     = $ps
    $capturedHandle = $handle
    $capturedTool   = $Tool
    $capturedSync   = $sync

    $timer          = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [System.TimeSpan]::FromMilliseconds(100)

    $timer.Add_Tick({
        if ($capturedPs.InvocationStateInfo.State -ne [System.Management.Automation.PSInvocationState]::Running) {
            $timer.Stop()
            try { $capturedPs.EndInvoke($capturedHandle) } catch { }
            $capturedPs.Dispose()

            $lastRun = $capturedSync.ToolRuns |
                       Where-Object { $_.Id -eq $capturedTool.Id } |
                       Select-Object -Last 1
            $finalStatus = if ($lastRun) { $lastRun.Status } else { 'Unknown' }

            Set-GuiIdle -ToolName $capturedTool.Name -Status $finalStatus
        }
    }.GetNewClosure())

    $timer.Start()
}

# ---- Disruptive confirm dialog ------------------------------------------
function Invoke-DisruptiveConfirmDialog {
    param([hashtable]$Tool)
    $sync = $script:GuiSync

    [xml]$xml = $script:ConfirmDialogXaml
    $dlg      = [System.Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($xml))
    $dlg.Owner = $sync.Window

    $dlg.FindName('DialogHeader').Text      = ('{0} - DISRUPTIVE OPERATION' -f $Tool.Name)
    $dlg.FindName('DialogDescription').Text = $Tool.Description

    $confirmBox = $dlg.FindName('ConfirmTextBox')
    $proceedBtn = $dlg.FindName('ProceedButton')
    $cancelBtn  = $dlg.FindName('CancelButton')

    $confirmBox.Add_TextChanged({
        $proceedBtn.IsEnabled = ($confirmBox.Text.Trim() -eq 'CONFIRM')
    })

    $dlg.Add_KeyDown({
        if ($_.Key -eq [System.Windows.Input.Key]::Escape) {
            $dlg.DialogResult = $false
        }
    })

    $proceedBtn.Add_Click({ $dlg.DialogResult = $true })
    $cancelBtn.Add_Click({  $dlg.DialogResult = $false })

    if ($dlg.ShowDialog()) {
        Invoke-GuiToolRun -Tool $Tool
    }
}

# ---- Ticket export dialog -----------------------------------------------
function Invoke-TicketExportDialog {
    $sync = $script:GuiSync

    [xml]$xml  = $script:TicketExportDialogXaml
    $dlg       = [System.Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($xml))
    $dlg.Owner = $sync.Window

    $ticketText = Export-TicketSummary
    $ticketBox  = $dlg.FindName('TicketTextBox')
    $statusLbl  = $dlg.FindName('SaveStatusLabel')
    $copyBtn    = $dlg.FindName('CopyButton')
    $saveBtn    = $dlg.FindName('SaveButton')
    $closeBtn   = $dlg.FindName('CloseButton')

    $ticketBox.Text = $ticketText

    $copyBtn.Add_Click({
        try {
            [System.Windows.Clipboard]::SetText($ticketBox.Text)
            $copyBtn.Content = 'Copied!'
            $statusTimer = [System.Windows.Threading.DispatcherTimer]::new()
            $statusTimer.Interval = [System.TimeSpan]::FromMilliseconds(1500)
            $capturedBtn   = $copyBtn
            $capturedTimer = $statusTimer
            $statusTimer.Add_Tick({
                $capturedBtn.Content = 'Copy to Clipboard'
                $capturedTimer.Stop()
            }.GetNewClosure())
            $statusTimer.Start()
        } catch {
            $statusLbl.Text = ('Copy failed: {0}' -f $_)
        }
    })

    $saveBtn.Add_Click({
        try {
            $stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
            $desktop = [Environment]::GetFolderPath('Desktop')
            $path    = Join-Path $desktop ('NMM-TicketSummary-{0}.txt' -f $stamp)
            Set-Content -Path $path -Value $ticketBox.Text -Encoding UTF8 -ErrorAction Stop
            $statusLbl.Foreground = ConvertTo-WpfBrush '#4EC94E'
            $statusLbl.Text       = ('Saved to {0}' -f $path)
        } catch {
            $statusLbl.Foreground = ConvertTo-WpfBrush '#F44747'
            $statusLbl.Text       = ('Save failed: {0}' -f $_)
        }
    })

    $closeBtn.Add_Click({ $dlg.Close() })
    $dlg.Add_KeyDown({
        if ($_.Key -eq [System.Windows.Input.Key]::Escape) { $dlg.Close() }
    })

    $dlg.ShowDialog() | Out-Null
}

# ---- STA GUI entry point ------------------------------------------------
function Start-GuiMenuSTA {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    [xml]$xml   = $script:MainWindowXaml
    $window     = [System.Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($xml))

    # Initialize shared sync table
    $script:GuiSync = [System.Collections.Hashtable]::Synchronized(@{
        Dispatcher           = $window.Dispatcher
        Window               = $window
        OutputBox            = $window.FindName('OutputBox')
        OutputPlaceholder    = $window.FindName('OutputPlaceholder')
        ScrollToBottomButton = $window.FindName('ScrollToBottomButton')
        PromptArea           = $window.FindName('PromptArea')
        PromptTextBlock      = $window.FindName('PromptTextBlock')
        PromptDefaultLabel   = $window.FindName('PromptDefaultLabel')
        ChoiceButtonsPanel   = $window.FindName('ChoiceButtonsPanel')
        StatusLabel          = $window.FindName('StatusLabel')
        RunButton            = $window.FindName('RunButton')
        RunProgressBar       = $window.FindName('RunProgressBar')
        CategoryNavPanel     = $window.FindName('CategoryNavPanel')
        ToolListBox          = $window.FindName('ToolListBox')
        ExportTicketButton   = $window.FindName('ExportTicketButton')
        SearchBox            = $window.FindName('SearchBox')
        SearchClearButton    = $window.FindName('SearchClearButton')
        ToolNameLabel        = $window.FindName('ToolNameLabel')
        CategoryChip         = $window.FindName('CategoryChip')
        CategoryChipText     = $window.FindName('CategoryChipText')
        RiskChip             = $window.FindName('RiskChip')
        RiskChipText         = $window.FindName('RiskChipText')
        AdminChip            = $window.FindName('AdminChip')
        DescriptionLabel     = $window.FindName('DescriptionLabel')
        TagsPanel            = $window.FindName('TagsPanel')
        AdminRefusedLabel    = $window.FindName('AdminRefusedLabel')
        ConfirmBanner        = $window.FindName('ConfirmBanner')
        ConfirmBannerText    = $window.FindName('ConfirmBannerText')
        ConfirmRunButton     = $window.FindName('ConfirmRunButton')
        ConfirmCancelButton  = $window.FindName('ConfirmCancelButton')
        CopyOutputButton     = $window.FindName('CopyOutputButton')
        ClearOutputButton    = $window.FindName('ClearOutputButton')
        ToolDetailCard       = $window.FindName('ToolDetailCard')
        ToolDetailPlaceholder = $window.FindName('ToolDetailPlaceholder')
        MachineUserLabel     = $window.FindName('MachineUserLabel')
        AdminBadge           = $window.FindName('AdminBadge')
        AdminBadgeText       = $window.FindName('AdminBadgeText')
        SessionTimerLabel    = $window.FindName('SessionTimerLabel')
        # State
        SelectedTool         = $null
        SelectedCategory     = 'Diagnostics'
        AutoScrollEnabled    = $true
        RunState             = 'Idle'
        PromptSemaphore      = [System.Threading.SemaphoreSlim]::new(0, 1)
        PromptResponse       = $null
        ToolRuns             = $script:ToolRuns
        ToolRunspace         = $null
        SessionStart         = $script:SessionStart
    })

    $sync = $script:GuiSync

    # Window title and header
    $window.Title              = ('NMM Toolkit v9 - {0}' -f $env:COMPUTERNAME)
    $sync.MachineUserLabel.Text = ('{0}\{1}' -f $env:COMPUTERNAME, $env:USERNAME)

    if ($script:IsAdmin) {
        $sync.AdminBadge.Background    = ConvertTo-WpfBrush '#1A3A1A'
        $sync.AdminBadgeText.Text       = '[ADMIN]'
        $sync.AdminBadgeText.Foreground = ConvertTo-WpfBrush '#4EC94E'
    } else {
        $sync.AdminBadge.Background    = ConvertTo-WpfBrush '#3A1A1A'
        $sync.AdminBadgeText.Text       = '[NOT ADMIN]'
        $sync.AdminBadgeText.Foreground = ConvertTo-WpfBrush '#F44747'
    }

    # Create the long-lived tool Runspace
    $sync.ToolRunspace = New-NmmToolRunspace

    # Build category nav buttons
    $categories = @('Common Fixes', 'Browser', 'Cloud', 'Diagnostics', 'Laptop',
                     'QuickFix', 'Repair', 'Security', 'User')

    foreach ($cat in $categories) {
        $catColor = if ($script:CategoryColors.ContainsKey($cat)) {
            $script:CategoryColors[$cat]
        } else { '#858585' }

        # Tool count label
        if ($cat -eq 'Common Fixes') {
            $countText = '(6)'
        } else {
            $count = @(Get-NmmTools | Where-Object { $_.Category -eq $cat }).Count
            $countText = "($count)"
        }

        $btn = [System.Windows.Controls.Button]::new()
        $btn.Tag = $cat

        # Button content: DockPanel with colored accent bar + text
        $dp = [System.Windows.Controls.DockPanel]::new()

        $accent = [System.Windows.Controls.Border]::new()
        $accent.Width      = 4
        $accent.Background = ConvertTo-WpfBrush $catColor
        $accent.Visibility = [System.Windows.Visibility]::Hidden
        [System.Windows.Controls.DockPanel]::SetDock($accent, [System.Windows.Controls.Dock]::Left)
        [void]$dp.Children.Add($accent)

        $label = [System.Windows.Controls.TextBlock]::new()
        if ($cat -eq 'Common Fixes') {
            $label.Text = ([char]0x2605 + ' Common Fixes')
        } else {
            $label.Text = $cat
        }
        $label.Foreground       = ConvertTo-WpfBrush '#CCCCCC'
        $label.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $label.Margin           = [System.Windows.Thickness]::new(8,0,0,0)
        [void]$dp.Children.Add($label)

        $countLbl = [System.Windows.Controls.TextBlock]::new()
        $countLbl.Text        = $countText
        $countLbl.Foreground  = ConvertTo-WpfBrush '#505050'
        $countLbl.FontSize    = 10
        $countLbl.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $countLbl.Margin      = [System.Windows.Thickness]::new(4,0,8,0)
        [System.Windows.Controls.DockPanel]::SetDock($countLbl, [System.Windows.Controls.Dock]::Right)
        [void]$dp.Children.Add($countLbl)

        $btn.Content    = $dp
        $btn.Height     = 34
        $btn.Background = [System.Windows.Media.Brushes]::Transparent
        $btn.BorderThickness = [System.Windows.Thickness]::new(0)
        $btn.HorizontalContentAlignment = [System.Windows.HorizontalAlignment]::Stretch
        $btn.Cursor     = [System.Windows.Input.Cursors]::Hand

        $capturedCat    = $cat
        $capturedAccent = $accent
        $capturedLabel  = $label
        $capturedColor  = $catColor

        $btn.Add_Click({
            # Deselect all nav buttons
            foreach ($child in $sync.CategoryNavPanel.Children) {
                $childDp = $child.Content
                if ($null -ne $childDp -and $childDp -is [System.Windows.Controls.DockPanel]) {
                    $accentBorder = $childDp.Children | Select-Object -First 1
                    if ($accentBorder) { $accentBorder.Visibility = [System.Windows.Visibility]::Hidden }
                    $child.Background = [System.Windows.Media.Brushes]::Transparent
                }
            }
            # Select this button
            $capturedAccent.Visibility = [System.Windows.Visibility]::Visible
            $sync.SelectedCategory = $capturedCat
            $sync.SearchBox.Text   = ''
            Update-ToolList -Window $null
        }.GetNewClosure())

        [void]$sync.CategoryNavPanel.Children.Add($btn)

        # Separator after Common Fixes
        if ($cat -eq 'Common Fixes') {
            $sep = [System.Windows.Controls.Separator]::new()
            $sep.Background = ConvertTo-WpfBrush '#3E3E42'
            $sep.Margin     = [System.Windows.Thickness]::new(8,4,8,4)
            [void]$sync.CategoryNavPanel.Children.Add($sep)
        }
    }

    # Default selection: Common Fixes if usage exists, else Diagnostics
    $defaultCat  = 'Diagnostics'
    $commonCount = (Get-NmmCommonFixes -Max 1).Count
    if ($commonCount -gt 0) { $defaultCat = 'Common Fixes' }
    $sync.SelectedCategory = $defaultCat

    # Activate the default nav button
    foreach ($child in $sync.CategoryNavPanel.Children) {
        if ($child -is [System.Windows.Controls.Button] -and $child.Tag -eq $defaultCat) {
            $childDp = $child.Content
            if ($childDp -is [System.Windows.Controls.DockPanel]) {
                $accentBorder = $childDp.Children | Select-Object -First 1
                if ($accentBorder) { $accentBorder.Visibility = [System.Windows.Visibility]::Visible }
            }
            $child.Background = ConvertTo-WpfBrush '#2A2A2E'
            break
        }
    }

    Update-ToolList -Window $window

    # ToolListBox SelectionChanged
    $sync.ToolListBox.Add_SelectionChanged({
        $selected = $sync.ToolListBox.SelectedItem
        if ($null -eq $selected) { return }
        if ($selected -isnot [System.Windows.Controls.ListBoxItem]) { return }
        $tool = $selected.Tag
        if ($null -eq $tool) { return }
        Update-DetailCard -Tool $tool
    })

    # Double-click to run
    $sync.ToolListBox.Add_MouseDoubleClick({
        $selected = $sync.ToolListBox.SelectedItem
        if ($null -eq $selected) { return }
        if ($selected -isnot [System.Windows.Controls.ListBoxItem]) { return }
        $tool = $selected.Tag
        if ($null -eq $tool) { return }
        if ($sync.RunState -eq 'Running') { return }
        if ($tool.RequiresAdmin -and -not $script:IsAdmin) { return }
        if ($tool.Risk -eq 'Modifies') {
            $sync.ConfirmBanner.Visibility = [System.Windows.Visibility]::Visible
            $sync.RunButton.Visibility     = [System.Windows.Visibility]::Collapsed
        } elseif ($tool.Risk -eq 'Disruptive') {
            Invoke-DisruptiveConfirmDialog -Tool $tool
        } else {
            Invoke-GuiToolRun -Tool $tool
        }
    })

    # RunButton
    $sync.RunButton.Add_Click({
        $tool = $sync.SelectedTool
        if ($null -eq $tool) { return }
        if ($sync.RunState -eq 'Running') { return }
        if ($tool.Risk -eq 'Modifies') {
            $sync.ConfirmBanner.Visibility = [System.Windows.Visibility]::Visible
            $sync.RunButton.Visibility     = [System.Windows.Visibility]::Collapsed
        } elseif ($tool.Risk -eq 'Disruptive') {
            Invoke-DisruptiveConfirmDialog -Tool $tool
        } else {
            Invoke-GuiToolRun -Tool $tool
        }
    })

    # ConfirmRunButton / ConfirmCancelButton
    $sync.ConfirmRunButton.Add_Click({
        $tool = $sync.SelectedTool
        if ($null -eq $tool) { return }
        $sync.ConfirmBanner.Visibility = [System.Windows.Visibility]::Collapsed
        $sync.RunButton.Visibility     = [System.Windows.Visibility]::Visible
        Invoke-GuiToolRun -Tool $tool
    })

    $sync.ConfirmCancelButton.Add_Click({
        $sync.ConfirmBanner.Visibility = [System.Windows.Visibility]::Collapsed
        $sync.RunButton.Visibility     = [System.Windows.Visibility]::Visible
    })

    # Search
    $sync.SearchBox.Add_TextChanged({
        $text = $sync.SearchBox.Text
        $sync.SearchClearButton.Visibility = if ($text.Length -gt 0) {
            [System.Windows.Visibility]::Visible
        } else {
            [System.Windows.Visibility]::Collapsed
        }
        Update-ToolList -Window $null
    })

    $sync.SearchClearButton.Add_Click({
        $sync.SearchBox.Text = ''
    })

    # Ctrl+F focuses search
    $window.Add_KeyDown({
        if ($_.Key -eq [System.Windows.Input.Key]::F -and
            [System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) {
            $sync.SearchBox.Focus() | Out-Null
            $_.Handled = $true
        }
    })

    # Auto-scroll tracking
    $sync.OutputBox.Add_ScrollChanged({
        $sb = $sync.OutputBox
        $atBottom = ($sb.VerticalOffset -ge ($sb.ScrollableHeight - 20))
        $sync.AutoScrollEnabled = $atBottom
        if ($atBottom) {
            $sync.ScrollToBottomButton.Visibility = [System.Windows.Visibility]::Collapsed
        }
    })

    $sync.ScrollToBottomButton.Add_Click({
        $sync.OutputBox.ScrollToEnd()
        $sync.AutoScrollEnabled = $true
        $sync.ScrollToBottomButton.Visibility = [System.Windows.Visibility]::Collapsed
    })

    # ClearOutputButton
    $sync.ClearOutputButton.Add_Click({
        $sync.OutputBox.Document.Blocks.Clear()
        $sync.AutoScrollEnabled = $true
        $sync.ScrollToBottomButton.Visibility = [System.Windows.Visibility]::Collapsed
        $sync.OutputPlaceholder.Visibility    = [System.Windows.Visibility]::Visible
    })

    # CopyOutputButton
    $sync.CopyOutputButton.Add_Click({
        try {
            $range = [System.Windows.Documents.TextRange]::new(
                $sync.OutputBox.Document.ContentStart,
                $sync.OutputBox.Document.ContentEnd)
            [System.Windows.Clipboard]::SetText($range.Text)
        } catch { }
    })

    # ExportTicketButton
    $sync.ExportTicketButton.Add_Click({
        Invoke-TicketExportDialog
    })

    # Session timer
    $timerStart   = $script:SessionStart
    $sessionTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $sessionTimer.Interval = [System.TimeSpan]::FromSeconds(1)
    $capturedSync  = $sync
    $capturedStart = $timerStart
    $sessionTimer.Add_Tick({
        $elapsed = (Get-Date) - $capturedStart
        $capturedSync.SessionTimerLabel.Text = ('Session: {0:hh\:mm\:ss}' -f $elapsed)
    }.GetNewClosure())
    $sessionTimer.Start()

    # Show window
    $window.ShowDialog() | Out-Null

    # Cleanup
    $sessionTimer.Stop()
    if ($sync.ToolRunspace) {
        try { $sync.ToolRunspace.Close()   } catch { }
        try { $sync.ToolRunspace.Dispose() } catch { }
    }
}

# ---- Public entry point (STA wrapper) -----------------------------------
function Start-GuiMenu {
    $apartmentState = [System.Threading.Thread]::CurrentThread.GetApartmentState()
    if ($apartmentState -ne [System.Threading.ApartmentState]::STA) {
        $uiThread = [System.Threading.Thread]::new(
            [System.Threading.ThreadStart]{ Start-GuiMenuSTA })
        $uiThread.SetApartmentState([System.Threading.ApartmentState]::STA)
        $uiThread.Name         = 'NMMTools-WPF'
        $uiThread.IsBackground = $false
        $uiThread.Start()
        $uiThread.Join()
    } else {
        Start-GuiMenuSTA
    }
}
