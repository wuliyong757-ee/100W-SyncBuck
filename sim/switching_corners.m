%% 100W Sync Buck - 时域极端工况: 36V 和 60V 两端都跑得动吗?
%  36V = 占空比最大 (D=33%), 器件电流应力最大
%  60V = 占空比最小 (D=20%), 环路带宽最宽
%  同一套 Type III 补偿器不改, 只改输入电压 —— 验证输入前馈确实把 Vin 约掉了
%
%  跑法: matlab -batch "switching_corners"
clear; clc; close all;

L=12e-6; C=422e-6; ESR=4e-3; fsw=300e3; Ts=1/fsw;
Vref=0.8; RFB1=20e3; RFB2=1428.6; Kd=RFB2/(RFB1+RFB2);
wi=4141.2; wz1=2*pi*1118.25; wz2=2*pi*2236.5; wp1=2*pi*94286; wp2=2*pi*150000;

Vins=[36 60];
t_ss=1.5e-3; t_step=3.0e-3; t_end=4.2e-3;
Io_lo=2; Io_hi=8;
h=Ts/120; N=round(t_end/h);

fprintf('==== 极端输入电压时域验证 ====\n');
fprintf('  软启动 %.1f ms, 负载跳变 %.1f->%.1f A @ %.1f ms\n\n', ...
        t_ss*1e3, Io_lo, Io_hi, t_step*1e3);

R=struct();
for vi=1:numel(Vins)
  Vin=Vins(vi); Vramp=Vin/15;
  x=[0;0;0;0;0];
  T=zeros(1,N); Vo=T; ILa=T; Ild=T; Duty=T; VrampA=T;
  rhs=@(tt,xx,il) buck_rhs(tt,xx,il,Vin,L,C,ESR,fsw,Vramp,Vref,Kd, ...
                            wi,wz1,wz2,wp1,wp2,t_ss);
  for k=1:N
    t=(k-1)*h;
    il = Io_lo + (Io_hi-Io_lo)*(t>=t_step);
    T(k)=t; Ild(k)=il;
    vout = x(2)+ESR*(x(1)-il);
    VrampA(k)=Vramp;
    Vo(k)=vout; ILa(k)=x(1);
    Duty(k) = (vout>0 && Vin>0) * min(max(vout/Vin,0),1);
    k1=rhs(t,x,il);
    k2=rhs(t+h/2,x+h/2*k1,il);
    k3=rhs(t+h/2,x+h/2*k2,il);
    k4=rhs(t+h,x+h*k3,il);
    x=x+h/6*(k1+2*k2+2*k3+k4);
  end

  % ---- 稳态指标 (4A 段取整段, 跳变前 0.4ms) ----
  ss = T>2.4e-3 & T<2.9e-3;
  vm = mean(Vo(ss)); vr = max(Vo(ss))-min(Vo(ss)); ipk = max(ILa(ss));
  if vr*1e3<=120, rv='PASS'; else, rv='FAIL'; end

  % ---- 负载跳变 ----
  tr = T>=t_step;
  vmin = min(Vo(tr));
  trec=NaN;
  for k=find(tr)
    if abs(Vo(k)-vm)<0.005*vm && all(abs(Vo(k:min(k+20000,N))-vm)<0.005*vm)
      trec=(T(k)-t_step)*1e6; break;
    end
  end

  fprintf('---- Vin = %d V   (占空比 %.0f%%) ----\n', Vin, 100*mean(Duty(ss)));
  fprintf('    稳态 Vout      = %.4f V\n', vm);
  fprintf('    纹波 pk-pk     = %.2f mV  (规格 <=120mV)  -> %s\n', vr*1e3, rv);
  fprintf('    iL 峰值        = %.2f A\n', ipk);
  fprintf('    跳变跌落       = %.1f mV (%.2f%%)  (规格 +/-600mV)\n', ...
          (vmin-vm)*1e3,(vmin-vm)/vm*100);
  if isnan(trec)
    fprintf('    恢复时间       = 窗口内未回稳\n\n');
  else
    fprintf('    恢复时间       = %.0f us  (规格 <200us)\n\n', trec);
  end

  R(vi).Vin=Vin; R(vi).T=T; R(vi).Vo=Vo; R(vi).IL=ILa; R(vi).Ild=Ild;
  R(vi).vm=vm; R(vi).vr=vr; R(vi).ipk=ipk; R(vi).vmin=vmin; R(vi).trec=trec;
end

%% ---------- 画图 ----------
f1=figure('Position',[60 40 1150 800],'Color','w');
for vi=1:numel(Vins)
  subplot(2,2,vi); hold on; grid on; box on;
  plot(R(vi).T*1e3,R(vi).Vo,'LineWidth',1.1,'Color',[0 0.45 0.74]);
  yline(12,'k--'); yline(12.6,'r:','+5%'); yline(11.4,'r:','-5%');
  title(sprintf('V_{in} = %d V   Vout', R(vi).Vin));
  ylabel('Vout (V)'); xlim([0 t_end*1e3]);
  if vi==1, ylim([-1 14]); else, ylim([-1 14]); end

  subplot(2,2,vi+2); hold on; grid on; box on;
  plot(R(vi).T*1e3,R(vi).IL,'LineWidth',1.1,'Color',[0.85 0.33 0.10]);
  plot(R(vi).T*1e3,R(vi).Ild,'LineWidth',1.0,'Color',[0.4 0.4 0.4],'LineStyle','--');
  yline(12,'m:','OCP 12A');
  title(sprintf('V_{in} = %d V   i_L  /  负载', R(vi).Vin));
  ylabel('电流 (A)'); xlabel('时间 (ms)'); xlim([0 t_end*1e3]); ylim([0 14]);
end
od=fileparts(mfilename('fullpath')); if isempty(od), od=pwd; end
saveas(f1,fullfile(od,'switching_corners.png'));
fprintf('Plot: %s\n', fullfile(od,'switching_corners.png'));

%% ---------- 本地函数 (与 switching_sim.m 同一个功率级模型) ----------
function dx = buck_rhs(t,x,il,Vin,L,C,ESR,fsw,Vramp,Vref,Kd,wi,wz1,wz2,wp1,wp2,t_ss)
  iL=x(1); vC=x(2); xi=x(3); x2=x(4); x3=x(5);
  vout = vC + ESR*(iL-il);
  vref_e = Vref*min(t/t_ss,1);
  e = vref_e - Kd*vout;
  y1 = xi;            d1 = wi*e;
  y2 = (wp1/wz1)*(y1 + (wz1-wp1)*x2);   d2 = -wp1*x2 + y1;
  y3 = (wp2/wz2)*(y2 + (wz2-wp2)*x3);   d3 = -wp2*x3 + y2;
  vcomp = y3/Kd;
  s = t*fsw - floor(t*fsw);
  on = vcomp > Vramp*s;
  if on, diL=(Vin-vout)/L; else, diL=-vout/L; end
  dx=[diL; (iL-il)/C; d1; d2; d3];
end
