// every word of the tour, in Arabic and English (claims only what Waad does; numbers from the system)
export type Lang = 'ar' | 'en';
export type Feature = {shot: string; kicker: string; title: string; gold: string[]; points: string[]};

export const COPY: Record<Lang, {
  hook1: string; hook2: string; hookGold: string[]; hookSub: string;
  features: Feature[];
  numbers: {to: number; label: string}[];
  cta: string; ctaGold: string[]; ctaSub: string;
}> = {
  ar: {
    hook1: 'منشأتك كاملة،', hook2: 'في نظام واحد', hookGold: ['نظام', 'واحد'],
    hookSub: 'الموارد البشرية · الرواتب · المالية · المبيعات · المخزون · المشاريع',
    features: [
      {shot: 'dash', kicker: 'الموارد البشرية', title: 'كل موظفيك في لوحة واحدة', gold: ['لوحة', 'واحدة'], points: ['الحضور والإجازات لحظة بلحظة', 'تنبيهات العقود والوثائق', 'التوطين والدوران بنظرة']},
      {shot: 'payroll', kicker: 'الرواتب', title: 'مسير رواتب حسب نظام العمل', gold: ['نظام', 'العمل'], points: ['الإضافي والغياب والتأمينات تلقائيا', 'اعتماد على ثلاث مراحل', 'ملف حماية الأجور وملف البنك']},
      {shot: 'compliance', kicker: 'الامتثال', title: 'امتثالك كاملا في صفحة واحدة', gold: ['صفحة', 'واحدة'], points: ['حماية الأجور والتأمينات', 'انتهاء الوثائق والعقود', 'متابعة نطاقات']},
      {shot: 'invoice', kicker: 'المبيعات', title: 'فواتير إلكترونية متوافقة مع زاتكا', gold: ['زاتكا'], points: ['فاتورة ضريبية برمز QR', 'عروض أسعار وأوامر بيع', 'تذكير العملاء بالمتأخرات']},
      {shot: 'reports', kicker: 'المالية', title: 'قوائم مالية تُحدَّث مع كل عملية', gold: ['كل', 'عملية'], points: ['قيود تلقائية من كل مستند', 'ميزان المراجعة والقوائم المالية', 'ضريبة القيمة المضافة والزكاة']},
      {shot: 'items', kicker: 'العمليات', title: 'المخزون والمشتريات والمشاريع', gold: ['والمشاريع'], points: ['مستودعات وجرد وتصنيع', 'دورة شراء كاملة', 'مشاريع ومستخلصات']},
    ],
    numbers: [{to: 370, label: 'نموذجا جاهزا بالعربي والإنجليزي'}, {to: 6, label: 'أقسام في نظام واحد'}, {to: 2, label: 'لغتان: العربية والإنجليزية'}, {to: 14, label: 'يوما تجربة مجانية'}],
    cta: 'جرّب وعد 14 يوما مجانا', ctaGold: ['مجانا'], ctaSub: 'دون بطاقة ائتمانية · حلول دقيقة.. لوعد موثوق',
  },
  en: {
    hook1: 'Your whole company,', hook2: 'in one system', hookGold: ['one', 'system'],
    hookSub: 'HR · Payroll · Finance · Sales · Inventory · Projects',
    features: [
      {shot: 'dash', kicker: 'Human resources', title: 'Your whole team on one dashboard', gold: ['one', 'dashboard'], points: ['Attendance and leave in real time', 'Contract and document alerts', 'Saudization and turnover at a glance']},
      {shot: 'payroll', kicker: 'Payroll', title: 'Payroll by the Saudi Labor Law', gold: ['Labor', 'Law'], points: ['Overtime, absence and GOSI calculated', 'Three-step approval', 'Wage protection and bank files']},
      {shot: 'compliance', kicker: 'Compliance', title: 'All your compliance on one page', gold: ['one', 'page'], points: ['Wage protection and GOSI', 'Expiring documents and contracts', 'Nitaqat follow-up']},
      {shot: 'invoice', kicker: 'Sales', title: 'ZATCA-compatible e-invoices', gold: ['ZATCA-compatible'], points: ['Tax invoices with a QR code', 'Quotations and sales orders', 'Overdue reminders to customers']},
      {shot: 'reports', kicker: 'Finance', title: 'Statements updated with every transaction', gold: ['every', 'transaction'], points: ['Automatic entries from every document', 'Trial balance and financial statements', 'VAT and zakat']},
      {shot: 'items', kicker: 'Operations', title: 'Inventory, purchasing and projects', gold: ['projects'], points: ['Warehouses, counts and manufacturing', 'A complete purchasing cycle', 'Projects and progress claims']},
    ],
    numbers: [{to: 370, label: 'ready forms in Arabic and English'}, {to: 6, label: 'modules in one system'}, {to: 2, label: 'languages: Arabic and English'}, {to: 14, label: 'days free trial'}],
    cta: 'Try Waad free for 14 days', ctaGold: ['free'], ctaSub: 'No credit card · Precise solutions, a promise you can trust',
  },
};
