%% 100W Sync Buck - 保护行为仿真
%  场景 1a: 满载启动, 软启动只有 1ms    -> 电容充电电流把谷值顶上去了吗?
%  场景 1b: 满载启动, 软启动按设计 12ms  -> 同一套硬件, 只是 CSS 够大
%  场景 2 : 先 2A 干净启动, 3ms 突加过流到 16A, 8ms 故障撤除
%  场景 3 : UVLO 上电 (Vin 20->45V 再降回 25V) -> 34V 才起振 / 32V 才关断
%  场景 4 : 输出短路 (3ms 起 0.1Ω 短接)  -> 逐周期限流 + 打嗝, 起不来
%  场景 5 : 反馈分压比漂移 15% (稳压点跑到 14.20V) -> 只有 OVP 能拦
%
%  ⚠️ 假设: 场景 1b 的 12ms 软启动 = CSS 150nF 对应的设计值, 尚未逐条对照原始手册.
%
%  模型说明 (与 switching_sim.m 同一个功率级, 加了保护逻辑):
%    - 限流判决 用 谷值 口径 (iL平均 - ΔiL/2). 谷值一越过阈值就当拍关断,
%      对应 LM5146 在下管导通末段采一眼、比较器立刻终止的那一下
%      (只在开关周期边界才判的话, 会白白多送一个周期, 电流冲过头 20%+)
%    - OVP 按 07-保护设计.md 7.10 的真实接法建模: LM393 输出拉低 EN 脚,
%      不是切输出线. 打嗝靠 VCC 掉电自然发生 -> 软启动时间本身就是打嗝周期
%
%  跑法: matlab -batch "protection_sim"
clear; clc; close all;

p.L=12e-6; p.C=422e-6; p.ESR=4e-3; p.fsw=300e3; p.Ts=1/p.fsw;
p.Vref=0.8; p.RFB1=20e3; p.RFB2=1428.6; p.Kd=p.RFB2/(p.RFB1+p.RFB2);
p.wi=4141.2; p.wz1=2*pi*1118.25; p.wz2=2*pi*2236.5;
p.xi_max=0.5;              % 积分器限幅 (抗饱和). 两个前导级直流增益=1, 故 vcomp=15*xi,
                           % xi=0.5 <-> vcomp 到 7.5V, 是 3.2V 斜坡的 2.3 倍余量.
                           % 稳态只要 xi~0.053 (48V 占空比 0.25), 不会影响正常调节
p.wp1=2*pi*94286; p.wp2=2*pi*150000;
p.Ilim=12;                 % OCP 阈值 (谷值口径) A
p.Ilim_neg=6;              % 反向电流限流 A. 本项目 SYNCIN 接 VCC = 强制 PWM(FPWM),
                           % 是允许倒灌的. 少了这一条, 输出预充电时重启会一路倒灌
p.knee=2;                  % 负载膝点电压 V

S=def_cfg(p); S(6)=def_cfg(p);   % 预分配 6 个 (场景数改了记得同步改这里)
k=0;

%% ---- 场景 1a: 满载启动, 软启动 1ms ----
k=k+1; S(k)=def_cfg(p);
S(k).name='场景1a  满载启动 (软启动 1ms)';
S(k).Io_fn=@(t,v) 8*min(max(v/p.knee,0),1);
S(k).t_end=6e-3;   S(k).h=p.Ts/60;  S(k).t_ss=1e-3;

%% ---- 场景 1b: 满载启动, 软启动 12ms (设计值) ----
k=k+1; S(k)=def_cfg(p);
S(k).name='场景1b  满载启动 (软启动 12ms, 设计值)';
S(k).Io_fn=@(t,v) 8*min(max(v/p.knee,0),1);
S(k).t_end=13.5e-3; S(k).h=p.Ts/40; S(k).t_ss=12e-3;

%% ---- 场景 2: 过流 2A -> 16A -> 2A ----
k=k+1; S(k)=def_cfg(p);
S(k).name='场景2  过流 2A->16A->2A (限流 + 打嗝 + 自恢复)';
S(k).Io_fn=@(t,v) (2+14*(t>=3e-3)-14*(t>=8e-3))*min(max(v/p.knee,0),1);
S(k).t_end=10e-3;  S(k).h=p.Ts/60;  S(k).t_ss=1e-3;

%% ---- 场景 3: UVLO 上电/掉电 ----
k=k+1; S(k)=def_cfg(p);
S(k).name='场景3  UVLO 上电 (Vin 20->45V 再降回 25V)';
S(k).Vin_fn=@(t) 20+25*min(t/2.5e-3,1)-20*min(max((t-4e-3)/2e-3,0),1);
S(k).Io_fn=@(t,v) 2*min(max(v/p.knee,0),1);
S(k).t_end=6e-3;   S(k).h=p.Ts/60;  S(k).t_ss=1e-3;

%% ---- 场景 4: 输出短路 (0.1Ω 短接) ----
k=k+1; S(k)=def_cfg(p);
S(k).name='场景4  输出短路 (3ms 起 0.1Ω 短接)';
S(k).Io_fn=@(t,v) (t<3e-3)*(2*min(max(v/p.knee,0),1)) + (t>=3e-3)*(v/0.1);
S(k).t_end=8e-3;   S(k).h=p.Ts/60;  S(k).t_ss=1e-3;

%% ---- 场景 5: 反馈分压比漂移 -> OVP ----
k=k+1; S(k)=def_cfg(p);
S(k).name='场景5  反馈分压比漂移15% (稳压点 12->14.20V, 8ms 缓漂)';
S(k).Io_fn=@(t,v) 2*min(max(v/p.knee,0),1);
% 缓漂而不是阶跃: 分压电阻的漂变是温漂/老化, 是慢慢跑掉的.
% 阶跃漂变会让环路积分器冲饱和 -> 电流先撞 OCP, 根本轮不到 OVP (已试过).
S(k).fbg_fn=@(t) p.Kd*(1-0.155*min(max((t-2e-3)/8e-3,0),1));   % 稳压点 0.8/fbg
S(k).ovp_en=true;  S(k).t_ovp_hic=1e-3;
S(k).t_end=14e-3;  S(k).h=p.Ts/40;  S(k).t_ss=1e-3;

%% ---- 跑 ----
fprintf('==== 保护行为仿真 ====\n');
fprintf('   OCP %g A (谷值口径) | UVLO 开%gV/关%gV | 打嗝 %gms\n', p.Ilim, S(1).UVon, S(1).UVoff, S(1).t_hic*1e3);
fprintf('   OVP 跳闸 %.2fV / 释放 %.2fV (LM393 拉低 EN, 见 07 文档 7.10)\n\n', S(1).Vov_trip, S(1).Vov_rel);

Rc=cell(1,numel(S));
for i=1:numel(S)
  r=run_case(S(i),p); Rc{i}=r;
  fprintf('---- %s ----\n', S(i).name);
  fprintf('    谷值电流峰值   = %.2f A   (OCP %.1f A, 余量 %+.0f%%)\n', ...
          r.valley_max, p.Ilim, (p.Ilim-r.valley_max)/r.valley_max*100);
  fprintf('    输出电流峰值   = %.2f A\n', r.iL_max);
  fprintf('    Vout 最低/最高 = %.2f V / %.2f V\n', r.vmin, r.vmax);
  if r.n_trip==0
    fprintf('    限流跳闸       = 0 次\n');
  else
    fprintf('    限流跳闸       = %d 次   第一次 @ %.2f ms\n', r.n_trip, r.t_first*1e3);
  end
  if S(i).ovp_en
    fprintf('    OVP 跳闸       = %d 次   第一次 @ %.2f ms\n', r.n_ovp, r.t_ovp_first*1e3);
  end
  if r.vin_start>0 && r.vin_start<1e3
    fprintf('    起振输入电压   = %.2f V   (UVLO 开点 %.0f V)\n', r.vin_start, S(i).UVon);
  end
  if r.vin_stop>0 && r.vin_stop<1e3
    fprintf('    关断输入电压   = %.2f V   (UVLO 关点 %.0f V)\n', r.vin_stop, S(i).UVoff);
  end
  fprintf('\n');
end
R=[Rc{:}];              % 收集成结构体数组, 供画图用

%% ---- 画图 ----
f1=figure('Position',[40 20 1200 820],'Color','w');
for i=1:numel(R)
  r=R(i);
  subplot(3,2,i);
  yyaxis left; hold on; grid on; box on;
  plot(r.T*1e3, r.valley,'LineWidth',1.1);
  yline(p.Ilim,'m--','OCP','LineWidth',1.0,'LabelHorizontalAlignment','left');
  ylabel('谷值电流 (A)'); ylim([-2 18]);
  yyaxis right;
  plot(r.T*1e3, r.Vo,'LineWidth',1.0,'Color',[0.3 0.6 0.3]);
  if S(i).ovp_en
    yline(S(i).Vov_trip,'r:','OVP','LineWidth',1.0,'LabelHorizontalAlignment','right');
  end
  ylabel('Vout (V)'); ylim([-2 18]);
  xlabel('时间 (ms)'); xlim([0 S(i).t_end*1e3]);
  title(S(i).name,'FontSize',8);
end
od=fileparts(mfilename('fullpath')); if isempty(od), od=pwd; end
saveas(f1,fullfile(od,'protection_sim.png'));
fprintf('Plot: %s\n', fullfile(od,'protection_sim.png'));

%% ================= 本地函数 =================
function c = def_cfg(p)
  c.name=''; c.Vin_fn=@(t) 48; c.Io_fn=@(t,v) 0; c.fbg_fn=@(t) p.Kd;
  c.t_end=6e-3; c.h=p.Ts/60; c.t_ss=1e-3; c.t_hic=2e-3;
  c.UVon=34; c.UVoff=32;
  c.ovp_en=false; c.t_ovp_hic=1e-3; c.Vov_trip=13.81; c.Vov_rel=13.14;
end

function out = run_case(cfg,p)
  h=cfg.h; N=round(cfg.t_end/h);
  x=[0;0;0;0;0];                 % [iL; vC; integ; lead1; lead2]
  ss_t=0; started=false; fault=false; ovp=false;
  t_fault=0; t_ovp=0;
  n_trip=0; n_ovp=0;
  t_first=NaN; t_ovp_first=NaN; vin_start=-1; vin_stop=-1;
  T=zeros(1,N); Vo=T; ILa=T; Ild=T; Vina=T; Valley=T;
  for k=1:N
    t=(k-1)*h;
    Vin=cfg.Vin_fn(t);
    % 负载电流依赖 vout, vout 又依赖负载电流 -> 先用上一步的负载电流估一次 vout
    if k==1, il_prev=0; else, il_prev=Ild(k-1); end
    vout0 = x(2)+p.ESR*(x(1)-il_prev);
    il = cfg.Io_fn(t, vout0);
    vout = x(2)+p.ESR*(x(1)-il);

    s = t*p.fsw - floor(t*p.fsw);
    newcyc = s < h*p.fsw;

    % 谷值电流 = 平均电流 - 半个电感纹波
    % (vout<0 时纹波公式不成立: 那时 on/off 两段电流都在涨, 谷值就是当拍的 iL)
    if vout>0
      Dk = min(max(vout/max(Vin,1e-6),0),1);
      dIL = vout*(1-Dk)/(p.L*p.fsw);
      valley = x(1) - dIL/2;
    else
      valley = x(1);
    end

    % ---- UVLO ----
    if ~started && Vin>cfg.UVon, started=true; ss_t=0; vin_start=Vin; end
    if started && Vin<cfg.UVoff, started=false; vin_stop=Vin; end

    % ---- 保护判决 ----
    % 限流: 谷值一越过阈值立刻关断 (比较器当拍终止, 不等周期边界).
    % 正反两个方向都要判: 反向那头不管的话, FPWM 下输出预充电重启会一路倒灌.
    if started && ~fault && ~ovp && isfinite(valley) && ...
       (valley>p.Ilim || valley<-p.Ilim_neg)
      fault=true; t_fault=t; x(3:5)=0; n_trip=n_trip+1;
      if isnan(t_first), t_first=t; end
    end

    if newcyc
      if fault && (t-t_fault)>cfg.t_hic, fault=false; ss_t=0; end

      % 外置 OVP (LM393 拉低 EN)
      if cfg.ovp_en
        if ~ovp && started && vout>cfg.Vov_trip
          ovp=true; t_ovp=t; x(3:5)=0; n_ovp=n_ovp+1;
          if isnan(t_ovp_first), t_ovp_first=t; end
        end
        if ovp && (t-t_ovp)>cfg.t_ovp_hic && vout<cfg.Vov_rel
          ovp=false; ss_t=0;
        end
      end
    end

    forceoff = (~started) || fault || ovp;
    if forceoff, ss_t=0; else, ss_t=ss_t+h; end
    fbg = cfg.fbg_fn(t);

    T(k)=t; Vo(k)=vout; ILa(k)=x(1); Ild(k)=il; Vina(k)=Vin;
    Valley(k)=valley;

    rhs=@(tt,xx) prot_rhs(tt,xx,il,forceoff,Vin,ss_t,cfg.t_ss,fbg,p);
    k1=rhs(t,x);
    k2=rhs(t+h/2,x+h/2*k1);
    k3=rhs(t+h/2,x+h/2*k2);
    k4=rhs(t+h,x+h*k3);
    x=x+h/6*(k1+2*k2+2*k3+k4);
  end

  ok = Valley<1e3 & Valley>-1e3;
  out.T=T; out.Vo=Vo; out.ILa=ILa; out.valley=Valley; out.Vina=Vina;
  out.valley_max = max(Valley(ok));
  out.iL_max     = max(ILa(ok));
  out.vmin       = min(Vo);  out.vmax = max(Vo);
  out.n_trip     = n_trip;   out.t_first = t_first;
  out.n_ovp      = n_ovp;    out.t_ovp_first = t_ovp_first;
  out.vin_start  = vin_start; out.vin_stop = vin_stop;
end

function dx = prot_rhs(t,x,il,forceoff,Vin,ss_t,t_ss,fbg,p)
  iL=x(1); vC=x(2); xi=x(3); x2=x(4); x3=x(5);
  vout = vC + p.ESR*(iL-il);
  vref_e = p.Vref*min(ss_t/t_ss,1);
  e = vref_e - fbg*vout;
  y1 = xi;            d1 = p.wi*e;
  % 抗积分饱和: 重启时输出还带着电, 误差会长期为负, 不限幅积分器会绕死
  if (xi>=p.xi_max && d1>0) || (xi<=-p.xi_max && d1<0), d1=0; end
  y2 = (p.wp1/p.wz1)*(y1 + (p.wz1-p.wp1)*x2);   d2 = -p.wp1*x2 + y1;
  y3 = (p.wp2/p.wz2)*(y2 + (p.wz2-p.wp2)*x3);   d3 = -p.wp2*x3 + y2;
  vcomp = y3/p.Kd;
  s = t*p.fsw - floor(t*p.fsw);
  if forceoff
    % 关断态: 上下管栅极都停了, 电感只能走体二极管. 三种情况都要处理:
    %   ① iL>0, vout>0  -> 下管体二极管续流, 电流衰减
    %   ② iL>0, vout<0  -> 下管体二极管反偏, 两个二极管都不通, 电流被"冻住"
    %   ③ iL<0         -> 反向电流把开关点顶到 Vin, 上管体二极管导通, 电流往回拉
    % ②③ 少任何一个都会出问题: 少了 ② 的 vout>0 条件, diL=-vout/L 变正反馈,
    % iL 跑飞到 29.5A; 少了 ③, 负电流被冻住后一直抽输出电容, vout 掉到 -5V.
    if iL>0 && vout>0
      diL=-vout/p.L;
    elseif iL<=0
      diL=(Vin-vout)/p.L;
    else
      diL=0;
    end
  else
    on = vcomp > (Vin/15)*s;
    if on, diL=(Vin-vout)/p.L; else, diL=-vout/p.L; end
  end
  dx=[diL; (iL-il)/p.C; d1; d2; d3];
end
