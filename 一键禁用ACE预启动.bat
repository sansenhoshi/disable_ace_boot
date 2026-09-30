@echo off
chcp 936 >nul 2>&1
setlocal EnableExtensions EnableDelayedExpansion

:: ==========================================================================
::  ACE-BOOT 服务处理工具
::  【重要】本文件必须保存为 ANSI(GBK) 编码 + CRLF 换行，不要存成 UTF-8。
::  功能：查询状态 -> 停止服务 -> 禁用开机自启动 -> 复核结果并汇总
::  权限：必须管理员运行（未提权时本脚本会自动弹出 UAC 请求提权）
::  编码：ANSI/GBK（代码页 936）+ CRLF 换行，严禁另存为 UTF-8，否则中文会乱码
::  说明：脚本只处理下面 SVC 变量指定的服务，默认 ACE-BOOT
:: ==========================================================================

set "SVC=ACE-BOOT"

set "QFILE=%TEMP%\ace-boot-query.tmp"
set "CFILE=%TEMP%\ace-boot-config.tmp"
set "RC_EXIST=0"
set "RC_STOP=0"
set "RC_CONF=0"
set "ST_BEFORE=未知"
set "ST_AFTER=未知"
set "START_BEFORE=未知"
set "START_AFTER=未知"
set "STOP_RESULT=未执行"
set "CONF_RESULT=未执行"

:: ====================== 第 0 步：管理员权限检查 / 自动提权 ==================
fltmc >nul 2>&1
if errorlevel 1 goto :ELEVATE
goto :MAIN

:ELEVATE
echo.
echo   当前不是管理员权限，正在请求提权，请在 UAC 弹窗中点“是”...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "try{$p=Start-Process -FilePath '%~f0' -Verb RunAs -WorkingDirectory '%~dp0' -Wait -PassThru; exit $p.ExitCode}catch{exit 1}"
if errorlevel 1 (
    echo.
    echo   【失败】提权被取消或失败。
    echo          请右键本文件，选择“以管理员身份运行”。
    echo.
    pause
    exit /b 1
)
exit /b 0

:MAIN
title %SVC% 服务处理工具 - 查询 / 停止 / 禁用自启动
cls
echo ==========================================================================
echo    %SVC% 服务处理工具
echo    服务名   : %SVC%
echo    执行账号 : %USERDOMAIN%\%USERNAME%
echo    执行时间 : %date% %time%
echo ==========================================================================
echo.

:: ============================== 第 1 步：查询 ==============================
echo [第 1 步 / 共 4 步] 查询服务是否存在、当前状态和启动类型
echo --------------------------------------------------------------------------
sc.exe query "%SVC%" >"%QFILE%" 2>&1
set "RC_EXIST=%errorlevel%"
type "%QFILE%"
echo.
if not "%RC_EXIST%"=="0" goto :NO_SERVICE

sc.exe qc "%SVC%" >"%CFILE%" 2>&1
type "%CFILE%"
echo.

findstr /C:"RUNNING" "%QFILE%" >nul 2>&1
if not errorlevel 1 set "ST_BEFORE=运行中 RUNNING"
findstr /C:"STOP_PENDING" "%QFILE%" >nul 2>&1
if not errorlevel 1 set "ST_BEFORE=正在停止 STOP_PENDING"
findstr /C:"STOPPED" "%QFILE%" >nul 2>&1
if not errorlevel 1 set "ST_BEFORE=已停止 STOPPED"

findstr /C:"BOOT_START" "%CFILE%" >nul 2>&1
if not errorlevel 1 set "START_BEFORE=引导启动 BOOT_START"
findstr /C:"SYSTEM_START" "%CFILE%" >nul 2>&1
if not errorlevel 1 set "START_BEFORE=系统启动 SYSTEM_START"
findstr /C:"AUTO_START" "%CFILE%" >nul 2>&1
if not errorlevel 1 set "START_BEFORE=自动 AUTO_START 【开机自启】"
findstr /C:"DEMAND_START" "%CFILE%" >nul 2>&1
if not errorlevel 1 set "START_BEFORE=手动 DEMAND_START"
findstr /C:"DISABLED" "%CFILE%" >nul 2>&1
if not errorlevel 1 set "START_BEFORE=已禁用 DISABLED"

echo 【查询结果】
echo    服务是否存在      : 是
echo    当前运行状态      : %ST_BEFORE%
echo    当前启动类型      : %START_BEFORE%
set "DRV1=%SystemRoot%\System32\drivers\%SVC%.sys"
set "DRV2=%ProgramFiles%\AntiCheatExpert\%SVC%.sys"
set "DRV_FOUND=0"
if exist "%DRV1%" set "DRV_FOUND=1"
if exist "%DRV2%" set "DRV_FOUND=1"
if exist "%DRV1%" echo    驱动文件          : %DRV1%  【存在】
if exist "%DRV2%" echo    驱动文件          : %DRV2%  【存在】
if "%DRV_FOUND%"=="0" echo    驱动文件          : 未在常见位置找到，可能已卸载或装在其它目录
echo.

:: ============================== 第 2 步：停止 ==============================
echo [第 2 步 / 共 4 步] 停止服务
echo --------------------------------------------------------------------------
if /i "%ST_BEFORE%"=="已停止 STOPPED" goto :STOP_SKIP
sc.exe stop "%SVC%"
set "RC_STOP=%errorlevel%"
if "%RC_STOP%"=="0" goto :STOP_OK
if "%RC_STOP%"=="1062" goto :STOP_INACTIVE
goto :STOP_FAIL

:STOP_SKIP
echo   【跳过】查询显示服务当前已经是停止状态，不需要再停止。
set "RC_STOP=0"
set "STOP_RESULT=无需处理，服务本来就是停止状态"
goto :AFTER_STOP

:STOP_OK
echo   【成功】停止指令执行成功，返回码 0。
set "STOP_RESULT=成功，已执行停止指令"
goto :AFTER_STOP

:STOP_INACTIVE
echo   【提示】返回码 1062：服务当前并未运行，效果等同于已停止。
set "RC_STOP=0"
set "STOP_RESULT=无需处理，服务未在运行"
goto :AFTER_STOP

:STOP_FAIL
echo   【失败】停止服务失败，返回码 %RC_STOP%。
call :HINT %RC_STOP%
set "STOP_RESULT=失败，返回码 %RC_STOP%"
goto :AFTER_STOP

:AFTER_STOP
ping -n 3 127.0.0.1 >nul 2>&1
sc.exe query "%SVC%" >"%QFILE%" 2>&1
findstr /C:"RUNNING" "%QFILE%" >nul 2>&1
if not errorlevel 1 set "ST_AFTER=仍在运行 RUNNING"
findstr /C:"STOP_PENDING" "%QFILE%" >nul 2>&1
if not errorlevel 1 set "ST_AFTER=正在停止 STOP_PENDING"
findstr /C:"STOPPED" "%QFILE%" >nul 2>&1
if not errorlevel 1 set "ST_AFTER=已停止 STOPPED"
echo   【复核】执行停止后，当前运行状态：%ST_AFTER%
echo.

:: ========================== 第 3 步：禁用开机自启 ==========================
echo [第 3 步 / 共 4 步] 禁用开机自启动，把启动类型改成 disabled
echo --------------------------------------------------------------------------
if /i "%START_BEFORE%"=="已禁用 DISABLED" echo   【提示】查询显示它本来就是禁用状态，下面再执行一次以确保生效。
sc.exe config "%SVC%" start= disabled
set "RC_CONF=%errorlevel%"
if "%RC_CONF%"=="0" goto :CONF_OK
goto :CONF_FAIL

:CONF_OK
echo   【成功】启动类型已设置为“禁用 disabled”，返回码 0，开机不会再自动加载。
set "CONF_RESULT=成功，启动类型已改为禁用 disabled"
goto :AFTER_CONF

:CONF_FAIL
echo   【失败】修改启动类型失败，返回码 %RC_CONF%。
call :HINT %RC_CONF%
set "CONF_RESULT=失败，返回码 %RC_CONF%"
goto :AFTER_CONF

:AFTER_CONF
echo.

:: ============================== 第 4 步：复核 ==============================
echo [第 4 步 / 共 4 步] 复核最终结果
echo --------------------------------------------------------------------------
sc.exe qc "%SVC%" >"%CFILE%" 2>&1
type "%CFILE%"
echo.
sc.exe query "%SVC%" >"%QFILE%" 2>&1
type "%QFILE%"
echo.

findstr /C:"RUNNING" "%QFILE%" >nul 2>&1
if not errorlevel 1 set "ST_AFTER=仍在运行 RUNNING"
findstr /C:"STOP_PENDING" "%QFILE%" >nul 2>&1
if not errorlevel 1 set "ST_AFTER=正在停止 STOP_PENDING"
findstr /C:"STOPPED" "%QFILE%" >nul 2>&1
if not errorlevel 1 set "ST_AFTER=已停止 STOPPED"

findstr /C:"BOOT_START" "%CFILE%" >nul 2>&1
if not errorlevel 1 set "START_AFTER=引导启动 BOOT_START"
findstr /C:"SYSTEM_START" "%CFILE%" >nul 2>&1
if not errorlevel 1 set "START_AFTER=系统启动 SYSTEM_START"
findstr /C:"AUTO_START" "%CFILE%" >nul 2>&1
if not errorlevel 1 set "START_AFTER=自动 AUTO_START 【仍会开机自启】"
findstr /C:"DEMAND_START" "%CFILE%" >nul 2>&1
if not errorlevel 1 set "START_AFTER=手动 DEMAND_START"
findstr /C:"DISABLED" "%CFILE%" >nul 2>&1
if not errorlevel 1 set "START_AFTER=已禁用 DISABLED 【不会再开机自启】"

echo ==========================================================================
echo                                处理结果汇总
echo ==========================================================================
echo    服务名称          : %SVC%
echo    查询结果          : 服务存在，查询成功
echo    处理前运行状态    : %ST_BEFORE%
echo    处理前启动类型    : %START_BEFORE%
echo    停止服务结果      : %STOP_RESULT%
echo    禁用自启动结果    : %CONF_RESULT%
echo    处理后运行状态    : %ST_AFTER%
echo    处理后启动类型    : %START_AFTER%
echo    命令返回码        : 停止 %RC_STOP% / 禁用 %RC_CONF%    0 表示成功
echo --------------------------------------------------------------------------
if not "%RC_STOP%"=="0" goto :NOT_PERFECT
if not "%RC_CONF%"=="0" goto :NOT_PERFECT
if /i "%ST_AFTER%"=="已停止 STOPPED" if /i "%START_AFTER%"=="已禁用 DISABLED 【不会再开机自启】" goto :ALL_GOOD
goto :NOT_PERFECT

:NOT_PERFECT
if /i "%ST_AFTER%"=="已停止 STOPPED" if /i "%START_AFTER%"=="已禁用 DISABLED 【不会再开机自启】" goto :OK_BUT_WARN
echo    结论：处理没有完全成功，请看上面标着【失败】的提示。
if /i "%ST_AFTER%"=="仍在运行 RUNNING" echo          服务仍在运行，可先重启电脑，再以管理员身份运行一次本脚本。
goto :TAIL

:OK_BUT_WARN
echo    结论：最终状态是对的（已停止 + 已禁止自启动），但中间有命令返回了非 0 返回码，
echo          多半是权限或反作弊保护导致，请对照上面的提示再确认一次。
goto :TAIL

:ALL_GOOD
echo    结论：全部完成 —— %SVC% 已停止，并且已禁止开机自启动。
goto :TAIL

:: ============================== 收尾与提示 ================================
:TAIL
echo ==========================================================================
echo    注意事项：
echo      1. 如果电脑里装了使用 ACE 反作弊的游戏，游戏启动或反作弊更新时可能把
echo         %SVC% 重新装回来并把启动类型改回自动，重新运行本脚本即可。
echo      2. 想改回原来的设置，用管理员 CMD 执行：
echo           sc config %SVC% start= demand     改回手动
echo           sc config %SVC% start= auto       改回开机自启
echo      3. 本脚本只动 %SVC%，不会修改其它任何服务。
echo --------------------------------------------------------------------------
echo    当前系统中名字以 ACE- 开头的服务 / 驱动列表：
sc.exe query type= all state= all | findstr /I /C:"SERVICE_NAME: ACE-"
echo.
echo    说明：上面这些其它 ACE 服务本脚本不做处理；若要一并处理，可把脚本里的
echo          set "SVC=ACE-BOOT" 改成对应服务名后再运行。
echo ==========================================================================
echo.
pause
exit /b 0

:: ============================== 服务不存在分支 ============================
:NO_SERVICE
echo 【查询结果】服务 "%SVC%" 不存在或无法查询，返回码 %RC_EXIST%。
echo    1060 = 指定的服务未安装，也就是系统里没有这个服务，无需处理。
call :HINT %RC_EXIST%
echo.
echo    结论：没有找到 %SVC%，脚本不做任何修改。
echo.
pause
exit /b 0

:: ============================== 错误码解释子程序 ==========================
:HINT
set "EC=%~1"
if "%EC%"=="5"    echo            原因：拒绝访问。请确认是管理员运行；若仍失败，多半是该服务被反作弊组件保护。
if "%EC%"=="1051" echo            原因：服务已被禁用，无法再接受该控制命令。
if "%EC%"=="1052" echo            原因：请求的控制命令对该服务无效。
if "%EC%"=="1053" echo            原因：服务没有及时响应启动或控制请求。
if "%EC%"=="1058" echo            原因：服务已被禁用，无法启动。
if "%EC%"=="1060" echo            原因：指定的服务未安装。
if "%EC%"=="1061" echo            原因：服务当前无法接受控制消息，请稍后重试。
if "%EC%"=="1062" echo            原因：服务尚未启动。
exit /b 0