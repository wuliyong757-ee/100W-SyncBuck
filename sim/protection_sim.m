%% 100W Sync Buck - 保护行为仿真
%  场景 1a: 满载启动, 软启动只有 1ms   -> 电容充电电流把谷值顶上去了吗?
%  场景 1b: 满载启动, 软启动按设计 12ms -> 同一套硬件, 只是 CSS 够大
%  场景 2 : 输出过流 8A -> 14A          -> 逐周期限流 + 打嗝重启
%  场景 3 : UVLO 上电 (Vin 20->45V 再降回 25V) -> 34V 才起振 / 32V 才关断
%
%  ⚠️ 假设: 场景 1b 的 12ms 软启动 = CSS 150nF 对应的设计值, 尚未逐条对照原始手册.
%
%  模型说明 (与 switching_sim.m 同一个功率级, 加了保护逻辑):
%    - 限流判决是 逐开关周期 做的, 用的是 谷值 口径 (iL平均 - ΔiL/2),
%      对应 LM5146 在下管导通末段采样的那一眼
%    - 触发后两个管子全关, 补偿器状态清零, 等 t_hic 后带软启动重新爬 (hiccup)
%    - 负载用带"膝点"的恒流源 (Vout<2V 时按比例减小), 避免输出被拉到负值
%
%  跑法: matlab -batch "protection_sim"
clear; clc; close all;

p.L=12e-6; p.C=422e-6; p.ESR=4e-3; p.fsw=300e3; p.Ts=1/p.fsw;
p.Vref=0.8; p.RFB1=20e3; p.RFB2=1428.6; p.Kd=p.RFB2/(p.RFB1+p.RFB2);
p.wi=4141.2; p.wz1=2*pi*1118.25; p.wz2=2*pi*2236.5;
p.wp1=2*pi*94286; p.wp2=2*pi*150000;
p.Ilim=12;                 % OCP 阈值 (谷值口径) A
p.knee=2;                  % 负载膝点电压 V

S=struct();

%% ---- 场景 1a: 满载启动, 软启动 1ms ----
S(1).name  = '场景1a  满载启动 (软启动 1ms)';
S(1).Vin_fn = @(t) 48;
S(1).Io_fn  = @(t) 8;
S(1).t_end  = 6e-3;   S(1).h = p.Ts/60;   S(1).t_ss = 1e-3;
S(1).t_hic  = 2e-3;   S(1).UVon = 34;     S(1).UVoff = 32;

%% ---- 场景 1b: 满载启动, 软启动 12ms (设计值) ----
S(2).name  = '场景1b  满载启动 (软启动 12ms, 设计值)';
S(2).Vin_fn = @(t) 48;
S(2).Io_fn  = @(t) 8;
S(2).t_end  = 13.5e-3; S(2).h = p.Ts/40;  S(2).t_ss = 12e-3;
S(2).t_hic  = 2e-3;    S(2).UVon = 34;    S(2).UVoff = 32;

%% ---- 场景 2: 先 2A 干净启动, 3ms 突加过流到 16A, 8ms 故障撤除 ----
S(3).name  = '场景2  过流 2A->16A->2A (逐周期限流 + 打嗝 + 自恢复)';
S(3).Vin_fn = @(t) 48;
S(3).Io_fn  = @(t) 2 + 14*(t>=3e-3) - 14*(t>=8e-3);
S(3).t_end  = 12e-3;  S(3).h = p.Ts/60;   S(3).t_ss = 1e-3;
S(3).t_hic  = 2e-3;   S(3).UVon = 34;     S(3).UVoff = 32;

%% ---- 场景 3: UVLO 上电/掉电 ----
S(4).name  = '场景3  UVLO 上电 (Vin 20->45V 再降回 25V)';
S(4).Vin_fn = @(t) 20 + 25*min(t/2.5e-3,1) - 20*min(max((t-4e-3)/2e-3,0),1);
S(4).Io_fn  = @(t) 2;
S(4).t_end  = 6e-3;   S(4).h = p.Ts/60;   S(4).t_ss = 1e-3;
S(4).t_hic  = 2e-3;   S(4).UVon = 34;     S(4).UVoff = 32;

%% ---- 跑 ----
fprintf('==== 保护行为仿真 ====\n');
fprintf('   OCP 阈值 %g A (谷值口径), UVLO 开 %gV / 关 %gV, 打嗝 %g ms\n\n', ...
        p.Ilim, S(1).UVon, S(1).UVoff, S(1).t_hic*1e3);

for i=1:numel(S)
  r = run_case(S(i), p);
  R(i)=r;  %#ok<SAGROW>

  fprintf('---- %s ----\n', S(i).name);
  fprintf('    谷值电流峰值   = %.2f A   (OCP 阈值 %.1f A, 余量 %+.0f%%)\n', ...
          r.valley_max, p.Ilim, (p.Ilim-r.valley_max)/r.valley_max*100);
  fprintf('    输出电流峰值   = %.2f A\n', r.iL_max);
  fprintf('    Vout 最低/最高 = %.2f V / %.2f V\n', r.vmin, r.vmax);
  if r.n_trip==0
    fprintf('    跳闸次数       = 0   -> 全程没触发限流\n');
  else
    fprintf('    跳闸次数       = %d   第一次 @ %.2f ms\n', r.n_trip, r.t_first*1e3);
  end
  if r.vin_start>0 && r.vin_start<1e3
    fprintf('    起振输入电压   = %.2f V   (UVLO 开点 %.0f V)\n', r.vin_start, S(i).UVon);
  end
  if r.vin_stop>0 && r.vin_stop<1e3
    fprintf('    关断输入电压   = %.2f V   (UVLO 关点 %.0f V)\n', r.vin_stop, S(i).UVoff);
  end
  fprintf('\n');
end

%% ---- 画图 ----
f1=figure('Position',[50 30 1180 800],'Color','w');
for i=1:numel(R)
  r=R(i);
  subplot(2,2,i);
  yyaxis left; hold on; grid on; box on;
  plot(r.T*1e3, r.valley, 'LineWidth',1.1);
  yline(p.Ilim,'m--','OCP','LineWidth',1.1,'LabelHorizontalAlignment','left');
  ylabel('谷值电流 (A)'); ylim([-2 16]);
  yyaxis right;
  plot(r.T*1e3, r.Vo,'LineWidth',1.0,'Color',[0.3 0.6 0.3]);
  ylabel('Vout (V)'); ylim([-2 16]);
  xlabel('时间 (ms)'); xlim([0 S(i).t_end*1e3]);
  title(S(i).name,'FontSize',9);
end
od=fileparts(mfilename('fullpath')); if isempty(od), od=pwd; end
saveas(f1,fullfile(od,'protection_sim.png'));
fprintf('Plot: %s\n', fullfile(od,'protection_sim.png'));

%% ================= 本地函数 =================
function out = run_case(cfg,p)
  h=cfg.h; N=round(cfg.t_end/h);
  x=[0;0;0;0;0];                 % [iL; vC; integ; lead1; lead2]
  ss_t=0; started=false; fault=false; t_fault=0;
  vmin=inf; n_trip=0; t_first=NaN; vin_start=-1; vin_stop=-1;
  was_started=false;
  T=zeros(1,N); Vo=T; ILa=T; Ild=T; Vina=T; Valley=T; Flt=T;
  for k=1:N
    t=(k-1)*h;
    Vin=cfg.Vin_fn(t);
    % 负载电流依赖 vout, vout 又依赖负载电流 -> 先用上一步的负载电流估一次 vout
    if k==1, il_prev = cfg.Io_fn(0); else, il_prev = Ild(k-1); end
    vout0 = x(2)+p.ESR*(x(1)-il_prev);
    il_cmd = cfg.Io_fn(t);
    il = il_cmd*min(max(vout0/p.knee,0),1);     % 带膝点的恒流负载
    vout = x(2)+p.ESR*(x(1)-il);

    s = t*p.fsw - floor(t*p.fsw);
    newcyc = s < h*p.fsw;

    % 谷值电流 = 平均电流 - 半个电感纹波
    Dk = min(max(vout/max(Vin,1e-6),0),1);
    dIL = vout*(1-Dk)/(p.L*p.fsw);
    valley = x(1) - dIL/2;

    % ---- UVLO ----
    if ~started && Vin>cfg.UVon
      started=true; ss_t=0;  vin_start=Vin;
    end
    if started && Vin<cfg.UVoff
      started=false; vin_stop=Vin;
    end

    % ---- 逐周期限流 + 打嗝 (只在开关周期边界判决) ----
    if newcyc
      if started && ~fault && isfinite(vmin) && vmin>p.Ilim
        fault=true; t_fault=t; x(3:5)=0; n_trip=n_trip+1;
        if isnan(t_first), t_first=t; end
      end
      if fault && (t-t_fault)>cfg.t_hic
        fault=false; ss_t=0;
      end
      vmin=inf;
    end
    if isfinite(valley), vmin=min(vmin,valley); end
    if ~started, ss_t=0; end
    forceoff = (~started) || fault;
    if forceoff
      if fault, ss_t=0; end
    else
      ss_t = ss_t + h;
    end

    T(k)=t; Vo(k)=vout; ILa(k)=x(1); Ild(k)=il; Vina(k)=Vin;
    Valley(k)=valley; Flt(k)=double(fault);

    rhs=@(tt,xx) prot_rhs(tt,xx,il,forceoff,Vin,ss_t,cfg.t_ss,p);
    k1=rhs(t,x);
    k2=rhs(t+h/2,x+h/2*k1);
    k3=rhs(t+h/2,x+h/2*k2);
    k4=rhs(t+h,x+h*k3);
    x=x+h/6*(k1+2*k2+2*k3+k4);

    if started && ~was_started, was_started=true; end
  end

  ok = Flt==0 & Valley<1e3 & Valley>-1e3;
  out.T=T; out.Vo=Vo; out.ILa=ILa; out.valley=Valley; out.Vina=Vina;
  out.valley_max = max(Valley(ok));
  out.iL_max     = max(ILa(ok));
  out.vmin       = min(Vo);  out.vmax = max(Vo);
  out.n_trip     = n_trip;
  out.t_first    = t_first;
  out.vin_start  = vin_start;
  out.vin_stop   = vin_stop;
end

function dx = prot_rhs(t,x,il,forceoff,Vin,ss_t,t_ss,p)
  iL=x(1); vC=x(2); xi=x(3); x2=x(4); x3=x(5);
  vout = vC + p.ESR*(iL-il);
  vref_e = p.Vref*min(ss_t/t_ss,1);
  e = vref_e - p.Kd*vout;
  y1 = xi;            d1 = p.wi*e;
  y2 = (p.wp1/p.wz1)*(y1 + (p.wz1-p.wp1)*x2);   d2 = -p.wp1*x2 + y1;
  y3 = (p.wp2/p.wz2)*(y2 + (p.wz2-p.wp2)*x3);   d3 = -p.wp2*x3 + y2;
  vcomp = y3/p.Kd;
  s = t*p.fsw - floor(t*p.fsw);
  if forceoff
    if iL>0, diL=-vout/p.L; else, diL=0; end
  else
    on = vcomp > (Vin/15)*s;
    if on, diL=(Vin-vout)/p.L; else, diL=-vout/p.L; end
  end
  dx=[diL; (iL-il)/p.C; d1; d2; d3];
end
