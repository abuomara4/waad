-- Waad ERP — 0066 the owner keeps «abdulaziz» as the team account; the extra «abdulaziz1» (0065) is not an admin.
delete from public.platform_admins where username = 'abdulaziz1';
