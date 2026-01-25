const SegmentedLine = ({ totalPages, currentIndex }) => {
	return (
		<div className="absolute top-10 right-3 left-5 flex justify-between md:top-16 md:right-16 md:left-16">
			{Array.from({ length: totalPages }).map((_, index) => (
				<div
					key={index.toString()}
					className={`mr-1 h-1 w-8 rounded-full bg-[#8ac3f8] md:mr-3 md:h-2 md:w-36 ${currentIndex >= index ? "bg-[#fff]" : ""}`}
				></div>
			))}
		</div>
	);
};

export default SegmentedLine;
