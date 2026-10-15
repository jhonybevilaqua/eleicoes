export function Logo({ className = '' }: { className?: string }) {
  return (
    <>
      <img className={`logo logo-verde ${className}`} src="/logo-verde.webp" alt="TV Evangelizar" />
      <img className={`logo logo-branca ${className}`} src="/logo-branca.webp" alt="TV Evangelizar" />
    </>
  );
}
