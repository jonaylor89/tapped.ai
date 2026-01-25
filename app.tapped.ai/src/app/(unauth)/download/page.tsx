import Image from "next/image";
import Footer from "@/components/Footer";
import DownloadTheAppSection from "@/components/profile/DownloadTheAppSection";

export default function Download() {
	return (
		<>
			<div className="flex flex-col items-center justify-center">
				<div className="px-4 py-24">
					<div className="hidden flex-0 py-4 lg:block">
						<Image src="/images/icon_1024.png" alt="Tapped App Icon" width={124} height={124} />
					</div>
					<DownloadTheAppSection showIcon={false} />
				</div>
			</div>
			<Footer />
		</>
	);
}
