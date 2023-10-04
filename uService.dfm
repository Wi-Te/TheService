object AService: TAService
  OldCreateOrder = False
  AllowPause = False
  DisplayName = 'to be set later'
  BeforeInstall = ServiceBeforeInstall
  AfterInstall = ServiceAfterInstall
  BeforeUninstall = ServiceBeforeUninstall
  OnShutdown = ServiceShutdown
  OnStart = ServiceStart
  OnStop = ServiceStop
  Left = 308
  Top = 178
  Height = 150
  Width = 216
end
