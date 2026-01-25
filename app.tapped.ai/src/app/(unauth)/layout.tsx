import TappedSheet from "@/components/TappedSheet";
import UnauthHeader from "@/components/unauth_header";

export default function UnauthLayout({ children }: { children: React.ReactNode }) {
	return (
		<>
			<TappedSheet />
			<div className="fixed top-0 z-50">
				<UnauthHeader />
			</div>
			<div className="transparent h-[4rem]" />
			{children}
		</>
	);
}
