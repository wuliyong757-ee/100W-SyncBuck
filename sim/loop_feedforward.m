%% 100W Sync Buck - 输入前馈真的把 Vin 从环路里消掉了吗?
%  被验证的说法 (README / 06-环路补偿.md):
%     "输入前馈把 Vin 从环路里消掉了 -> 36V / 48V / 60V 下穿越频率与相位裕度完全一样"
%
%  模型 (电压模式):
%     功率级 (占空比 -> 输出):  Gvd(s) = Vin * Hx(s)    <- 直流增益正比于 Vin
%     Hx(s) = (1 + s/wESR) / (1 + s/(Q*w0) + (s/w0)^2)
%
%     调制器 有前馈:  Fm = 15/Vin   (LM5146 斜坡跟随 Vin, 所以 Vin 被约掉)
%     调制器 无前馈:  Fm = 15/48    (固定斜坡 48/15 = 3.2V ; 两种情形在 48V 处对齐,
%                                    这样比较的是"随 Vin 漂移多少"而不是绝对水平)
%
%     环路增益  T(s) = Fm * Gvd(s) * Gc(s) * exp(-s*Td)     Td = Ts/2 采样延时
%
%  跑法: matlab -batch "loop_feedforward"
clear; clc; close all;

%% ---------- 沿用 loop_bode.m 的设计, 不改任何一个元件值 ----------
L=12e-6; Co=422e-6; ESR=4e-3; fsw=300e3; Vout=12;
w0=1/sqrt(L*Co); wesr=1/(ESR*Co);
wi=4141.2; wz1=2*pi*1118.25; wz2=2*pi*2236.5;
wp1=2*pi*94286; wp2=2*pi*150000; Td=0.5/fsw;

f=logspace(1,6,20000); s=1j*2*pi*f;
Gc=(wi./s).*(1+s/wz1).*(1+s/wz2)./((1+s./wp1).*(1+s./wp2));
Dly=exp(-s*Td);

Vins=[36 48 60];
loads=[8 1.5];              % 8A = 满载 ; 1.5A = 相位裕度最恶劣
names={'无前馈 (固定 3.2V 斜坡)','有前馈 (斜坡 = Vin/15)'};

%% ---------- 扫 Vin x 负载 ----------
fprintf('==== 输入前馈效果验证 ====\n');
fprintf('   两种调制器在 48V 处对齐, 所以看的是"随 Vin 漂移多少"\n\n');
summary=zeros(2,numel(Vins),2);   % [mode, Vin, {fc ; PM}]
for md=1:2
  fprintf('---- %s ----\n', names{md});
  fprintf('   Io     Vin     Q      fc(Hz)   PM(deg)   GM(dB)\n');
  for Io=loads
    R=Vout/Io; Qx=1/(w0*(L/R+ESR*Co));
    Hx=(1+s/wesr)./(1+s./(Qx*w0)+(s./w0).^2);
    for vi=1:numel(Vins)
      Vin=Vins(vi);
      if md==1, Fm=15/48; else, Fm=15/Vin; end
      T=Fm*Vin*Hx.*Gc.*Dly;
      m=20*log10(abs(T)); p=unwrap(angle(T))*180/pi;
      i1=find(m(1:end-1)>=0 & m(2:end)<0,1);
      ip=find(p(1:end-1)>-180 & p(2:end)<=-180,1);
      gmdb=NaN; if ~isempty(ip), gmdb=-m(ip); end
      fprintf('  %4.1fA  %3.0fV  %6.2f   %7.0f   %6.1f    %5.1f\n', ...
              Io,Vin,Qx,f(i1),180+p(i1),gmdb);
      if Io==loads(2), summary(md,vi,:)=[f(i1); 180+p(i1)]; end
    end
  end
  fprintf('\n');
end

%% ---------- 漂移量对比 (最恶劣负载 1.5A) ----------
fprintf('==== 随 Vin 的变化量 (1.5A, 最恶劣负载) ====\n');
for md=1:2
  fc=summary(md,:,1); pm=summary(md,:,2);
  fprintf('  %s:\n', names{md});
  fprintf('     fc  %6.0f -> %6.0f Hz   (变化 %+.1f%%)\n', fc(1),fc(3),(fc(3)-fc(1))/fc(1)*100);
  fprintf('     PM  %6.1f -> %6.1f deg  (变化 %+.1f 度)\n', pm(1),pm(3),pm(3)-pm(1));
end
fprintf('\n');

%% ---------- 画图 ----------
cols=[0.85 0.33 0.10; 0 0.45 0.74];      % 红=无前馈  蓝=有前馈
f1=figure('Position',[80 60 1080 780],'Color','w');
for sub=1:2
  subplot(2,1,sub); hold on; grid on; box on;
  for md=1:2
    for vi=1:numel(Vins)
      Vin=Vins(vi); Io=1.5; R=Vout/Io; Qx=1/(w0*(L/R+ESR*Co));
      Hx=(1+s/wesr)./(1+s./(Qx*w0)+(s./w0).^2);
      if md==1, Fm=15/48; ls='--'; else, Fm=15/Vin; ls='-'; end
      T=Fm*Vin*Hx.*Gc.*Dly;
      if sub==1, y=20*log10(abs(T)); else, y=unwrap(angle(T))*180/pi; end
      plot(f,y,ls,'Color',cols(md,:),'LineWidth',1.2, ...
           'DisplayName',sprintf('%s, Vin=%dV',names{md},Vin));
    end
  end
  if sub==1
    yline(0,'k--'); ylabel('幅值 (dB)'); ylim([-80 80]);
    title('输入前馈对环路增益的作用  (Io=1.5A, 含 Td=Ts/2)');
    legend('Location','southwest','FontSize',8);
  else
    yline(-135,'r--','PM=45');
    ylabel('相位 (度)'); xlabel('频率 (Hz)'); ylim([-270 0]);
  end
  xline(20e3,'k:','fc=20k');
  set(gca,'XScale','log'); xlim([10 1e6]);
end
od=fileparts(mfilename('fullpath')); if isempty(od), od=pwd; end
saveas(f1,fullfile(od,'loop_feedforward.png'));
fprintf('Plot: %s\n', fullfile(od,'loop_feedforward.png'));
