import ClientShell from "./ClientShell";

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
	return (
		<ClientShell>
			<main className="w-full">{children}</main>
		</ClientShell>
	);
}
