Unicode True

!ifndef APP_VERSION
  !define APP_VERSION "0.2.2"
!endif
!ifndef DIST_DIR
  !define DIST_DIR "dist"
!endif
!ifndef OUT_FILE
  !define OUT_FILE "out\ymusic-setup.exe"
!endif
!ifndef ICON_FILE
  !define ICON_FILE "icons\ymusic.ico"
!endif

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"

!define APP_NAME "Yandex Music"
!define APP_EXE "ymusic-qml.exe"
!define UNINSTALL_REG_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\YMusic"

Name "${APP_NAME}"
OutFile "${OUT_FILE}"
InstallDir "$LOCALAPPDATA\Programs\YMusic"
InstallDirRegKey HKCU "${UNINSTALL_REG_KEY}" "InstallLocation"
RequestExecutionLevel user
SetCompressor /SOLID lzma
ShowInstDetails show
ShowUnInstDetails show

!define MUI_ICON "${ICON_FILE}"
!define MUI_UNICON "${ICON_FILE}"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Запустить ${APP_NAME}"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "Russian"
!insertmacro MUI_LANGUAGE "English"

Section "${APP_NAME}" SecApp
  SectionIn RO

  ; During silent auto-updates the running process closes right after spawning setup.exe,
  ; so wait briefly until the main executable and core DLL are unlocked before overwriting.
  ${For} $R2 1 75
    ClearErrors
    ${If} ${FileExists} "$INSTDIR\${APP_EXE}"
      Delete "$INSTDIR\${APP_EXE}"
    ${EndIf}
    ${If} ${FileExists} "$INSTDIR\ymusic_core.dll"
      Delete "$INSTDIR\ymusic_core.dll"
    ${EndIf}
    ${IfNot} ${FileExists} "$INSTDIR\${APP_EXE}"
    ${AndIfNot} ${FileExists} "$INSTDIR\ymusic_core.dll"
      ${Break}
    ${EndIf}
    Sleep 200
  ${Next}
  Sleep 150

  SetOutPath "$INSTDIR"
  File /r "${DIST_DIR}\*.*"

  WriteUninstaller "$INSTDIR\Uninstall.exe"

  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\Удалить ${APP_NAME}.lnk" "$INSTDIR\Uninstall.exe"

  WriteRegStr HKCU "${UNINSTALL_REG_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKCU "${UNINSTALL_REG_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKCU "${UNINSTALL_REG_KEY}" "Publisher" "finrixx"
  WriteRegStr HKCU "${UNINSTALL_REG_KEY}" "DisplayIcon" "$INSTDIR\${APP_EXE},0"
  WriteRegStr HKCU "${UNINSTALL_REG_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_REG_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU "${UNINSTALL_REG_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKCU "${UNINSTALL_REG_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_REG_KEY}" "NoRepair" 1

  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKCU "${UNINSTALL_REG_KEY}" "EstimatedSize" "$0"
SectionEnd

Section "Ярлык на рабочем столе" SecDesktop
  ; Avoid recreating a desktop shortcut the user deleted when applying a silent update.
  ${IfNot} ${Silent}
  ${OrIf} ${FileExists} "$DESKTOP\${APP_NAME}.lnk"
    CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0
  ${EndIf}
SectionEnd

Function .onInstSuccess
  ${GetParameters} $R0
  ClearErrors
  ${GetOptions} $R0 "/RELAUNCH" $R1
  IfErrors done
  Exec '"$INSTDIR\${APP_EXE}"'
  done:
FunctionEnd

Section "Uninstall"
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\Удалить ${APP_NAME}.lnk"
  RMDir "$SMPROGRAMS\${APP_NAME}"
  Delete "$DESKTOP\${APP_NAME}.lnk"

  Delete "$INSTDIR\${APP_EXE}"
  Delete "$INSTDIR\Uninstall.exe"
  Delete "$INSTDIR\*.dll"
  Delete "$INSTDIR\*.conf"
  Delete "$INSTDIR\*.txt"
  RMDir /r "$INSTDIR\fonts"
  RMDir /r "$INSTDIR\qml"
  RMDir /r "$INSTDIR\platforms"
  RMDir /r "$INSTDIR\styles"
  RMDir /r "$INSTDIR\imageformats"
  RMDir /r "$INSTDIR\iconengines"
  RMDir /r "$INSTDIR\tls"
  RMDir /r "$INSTDIR\generic"
  RMDir /r "$INSTDIR\networkinformation"
  RMDir /r "$INSTDIR\platforminputcontexts"
  RMDir /r "$INSTDIR\multimedia"
  RMDir "$INSTDIR"

  DeleteRegKey HKCU "${UNINSTALL_REG_KEY}"
SectionEnd
