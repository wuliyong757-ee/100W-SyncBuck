%% 100W Sync Buck - 元件容差最坏情况分析
%
%  问题: 补偿器是按"名义值"设计的 (L=12µH, Co=422µF, ESR=4mΩ).
%        但实际元件会跑偏 —— 电感量有批次公差, 固态电容容量有公差, ESR 随温度变化更大.
%        **补偿器元件值锁死不动**(一块板只有一个 BOM), 让功率级跑偏, 看相位裕度还剩多少.
%
%  跑的维度:
%     L   ±20%        (电感量公差)
%     Co  ±20%        (固态电容容量公差)
%     ESR ×0.5 ~ ×2   (ESR 受温度/批次影响最大, 所以给最宽的窗口)
%     负载 1.5A ~ 8A   (Q 变化 3 倍, 轻载是最恶劣的)
%
%  两种跑法:
%     (1) 边角网格  —— 每个维度取端点, 组合出最坏情况, 可解释
%     (2) 蒙特卡洛  —— 随机撒点, 看相位裕度的分布, 不是只看一个点
%
%  跑法: matlab -batch "worst_case"
clear; clc; close all;

%% ---------- 锁死的补偿器 (与 loop_bode.m 完全一致, 一个数都不改) ----------
fsw=300e3; Vout=12; kFF=15; Td=0.5/fsw;
wi=4141.2; wz1=2*pi*1118.25; wz2=2*pi*2236.5;
wp1=2*pi*94286; wp2=2*pi*150000;

f=logspace(1,6,6000); s=1j*2*pi*f;
Gc=(wi./s).*(1+s/wz1).*(1+s/wz2)./((1+s./wp1).*(1+s./wp2));
Dly=exp(-s*Td);

%% ---------- 名义值 ----------
L0=12e-6; Co0=422e-6; ESR0=4e-3;
[fcn,pmn,gmn]=margins(L0,Co0,ESR0,8,f,s,Gc,Dly,kFF,Vout);
fprintf('==== 元件容差最坏情况分析 ====\n');
fprintf('  名义值: L=%.0fµH Co=%.0fµF ESR=%.1fmΩ @8A\n', L0*1e6, Co0*1e6, ESR0*1e3);
fprintf('          fc=%.0f Hz   PM=%.1f°   GM=%.1f dB\n\n', fcn, pmn, gmn);

%% ---------- (1) 边角网格 ----------
Ls  = L0*[0.8 1 1.2];
Cos = Co0*[0.8 1 1.2];
ESRs= ESR0*[0.5 1 2];
Ios = [1.5 4 8];

rows=[]; worst=struct('pm',999);
for L=Ls
 for Co=Cos
  for E=ESRs
   for Io=Ios
     [fc,pm,gm]=margins(L,Co,E,Io,f,s,Gc,Dly,kFF,Vout);
     if ~isnan(pm)
       rows(end+1,:)=[L*1e6 Co*1e6 E*1e3 Io fc pm gm]; %#ok<SAGROW>
       if pm<worst.pm, worst=struct('pm',pm,'fc',fc,'gm',gm,'L',L,'Co',Co,'E',E,'Io',Io); end
     end
   end
  end
 end
end

fprintf('  边角网格: %d 组合跑完\n', size(rows,1));
fprintf('  PM 分布: 最坏 %.1f°  /  中位 %.1f°  /  最好 %.1f°\n', ...
        min(rows(:,6)), median(rows(:,6)), max(rows(:,6)));
fprintf('  GM 最小 %.1f dB\n\n', min(rows(:,7)));

fprintf('  ---- 最坏组合 ----\n');
fprintf('    L=%.1fµH (%.0f%%), Co=%.1fµF (%.0f%%), ESR=%.1fmΩ (×%.1f), Io=%.1fA\n', ...
        worst.L*1e6,(worst.L/L0-1)*100, worst.Co*1e6,(worst.Co/Co0-1)*100, ...
        worst.E*1e3, worst.E/ESR0, worst.Io);
fprintf('    fc=%.0f Hz   PM=%.1f°   GM=%.1f dB\n', worst.fc, worst.pm, worst.gm);
if worst.pm>=45, v='PASS (>=45°)'; else, v='FAIL'; end
fprintf('    -> %s\n\n', v);

fprintf('  ---- 各维度单独拉满时的 PM ----\n');
dims={'L -20%','L +20%','Co -20%','Co +20%','ESR ×0.5','ESR ×2'};
pert=[Ls(1) Ls(3) L0 L0 L0 L0; Co0 Co0 Cos(1) Cos(3) Co0 Co0; ESR0 ESR0 ESR0 ESR0 ESRs(1) ESRs(3)];
for i=1:numel(dims)
  pmv=[];
  for Io=Ios
    [~,p1,~]=margins(pert(1,i),pert(2,i),pert(3,i),Io,f,s,Gc,Dly,kFF,Vout);
    pmv(end+1)=p1; %#ok<SAGROW>
  end
  fprintf('    %-9s  PM = %5.1f° ~ %5.1f°   (名义 %.1f°)\n', dims{i}, min(pmv), max(pmv), pmn);
end
fprintf('\n');

%% ---------- (2) 蒙特卡洛 ----------
Nm=1500;
rng(7);                                  % 固定种子, 结果可复现
Lm  = L0  *(0.8+0.4*rand(1,Nm));         % ±20% 均匀
Com = Co0 *(0.8+0.4*rand(1,Nm));         % ±20% 均匀
Em  = ESR0*(0.5+1.5*rand(1,Nm));         % ×0.5 ~ ×2 均匀
Iom = 1.5+6.5*rand(1,Nm);                % 1.5 ~ 8A 均匀

pmMC=nan(1,Nm); fcMC=nan(1,Nm);
for k=1:Nm
  [fc1,p1,~]=margins(Lm(k),Com(k),Em(k),Iom(k),f,s,Gc,Dly,kFF,Vout);
  pmMC(k)=p1; fcMC(k)=fc1;
end
ok=~isnan(pmMC); pmMC=pmMC(ok); fcMC=fcMC(ok);
pms=sort(pmMC);                       % 自己排序取分位, 免依赖统计工具箱
q01=pms(max(1,round(0.01*numel(pms))));
fprintf('  蒙特卡洛: %d 次抽样 (%d 次有效)\n', Nm, numel(pmMC));
fprintf('    PM  最坏 %.1f°  /  1%% 分位 %.1f°  /  中位 %.1f°  /  最好 %.1f°\n', ...
        min(pmMC), q01, median(pmMC), max(pmMC));
fprintf('    低于 45° 的比例: %.2f %%\n', mean(pmMC<45)*100);
fprintf('    fc  范围: %.0f ~ %.0f Hz  (名义 %.0f Hz)\n\n', min(fcMC), max(fcMC), fcn);

%% ---------- 画图 ----------
f1=figure('Position',[60 40 1150 780],'Color','w');

subplot(2,2,[1 3]); hold on; grid on; box on;
[f1n,p1n,~]=margins(L0,Co0,ESR0,1.5,f,s,Gc,Dly,kFF,Vout);
[f1w,p1w,~]=margins(worst.L,worst.Co,worst.E,worst.Io,f,s,Gc,Dly,kFF,Vout);
cs   = { [L0 Co0 ESR0 1.5], [worst.L worst.Co worst.E worst.Io] };
clab = { '名义 (L=12µH Co=422µF ESR=4mΩ, 1.5A)', ...
         sprintf('最坏组合 (L%.0f%% Co%.0f%% ESR×%.1f, %.1fA)', ...
                 (worst.L/L0-1)*100,(worst.Co/Co0-1)*100,worst.E/ESR0,worst.Io) };
cl   = [0 0.45 0.74; 0.85 0.33 0.10];
for i=1:2
  c=cs{i};
  w0=1/sqrt(c(1)*c(2)); we=1/(c(3)*c(2));
  R=Vout/c(4); Q=1/(w0*(c(1)/R+c(3)*c(2)));
  H=(1+s/we)./(1+s./(Q*w0)+(s./w0).^2);
  T=kFF*H.*Gc.*Dly;
  plot(f,20*log10(abs(T)),'Color',cl(i,:),'LineWidth',1.3,'DisplayName',clab{i});
  plot(f,unwrap(angle(T))*180/pi,'Color',cl(i,:),'LineWidth',1.3,'LineStyle','--', ...
       'HandleVisibility','off');
end
yline(0,'k:'); xline(20e3,'k:','fc=20k'); set(gca,'XScale','log');
xlim([10 1e6]); ylim([-270 80]);
xlabel('频率 (Hz)'); ylabel('幅值 (dB) / 相位 (度)');
title('容差边角: 幅值(实线) 与 相位(虚线)','FontSize',9);
legend('Location','southwest','FontSize',8);
text(20,40,sprintf('名义 PM=%.1f°\n最坏 PM=%.1f°',p1n,p1w),'FontSize',9,'Color','k');

subplot(2,2,2); hold on; grid on; box on;
histogram(pmMC,40,'FaceColor',[0 0.45 0.74]);
xline(45,'r--','线 45°','LineWidth',1.3);
xline(pmn,'k:','名义'); xline(min(pmMC),'m-','最坏');
xlabel('相位裕度 (度)'); ylabel('抽样数');
title(sprintf('蒙特卡洛 %d 次抽样的 PM 分布',numel(pmMC)),'FontSize',9);

subplot(2,2,4); hold on; grid on; box on;
histogram(fcMC/1e3,40,'FaceColor',[0.85 0.33 0.10]);
xline(fcn/1e3,'k:','名义');
xlabel('穿越频率 (kHz)'); ylabel('抽样数');
title('穿越频率分布','FontSize',9);

od=fileparts(mfilename('fullpath')); if isempty(od), od=pwd; end
saveas(f1,fullfile(od,'worst_case.png'));
fprintf('Plot: %s\n', fullfile(od,'worst_case.png'));

%% ================= 本地函数 =================
function [fc,pm,gm] = margins(L,Co,ESR,Io,f,s,Gc,Dly,kFF,Vout)
  w0=1/sqrt(L*Co); we=1/(ESR*Co);
  R=Vout/Io; Q=1/(w0*(L/R+ESR*Co));
  H=(1+s/we)./(1+s./(Q*w0)+(s./w0).^2);
  T=kFF*H.*Gc.*Dly;
  m=20*log10(abs(T)); p=unwrap(angle(T))*180/pi;
  i1=find(m(1:end-1)>=0 & m(2:end)<0,1);
  if isempty(i1), fc=NaN; pm=NaN; gm=NaN; return; end
  fc=f(i1); pm=180+p(i1);
  ip=find(p(1:end-1)>-180 & p(2:end)<=-180,1);
  if isempty(ip), gm=NaN; else, gm=-m(ip); end
end
